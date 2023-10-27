defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Encoder
  alias Hologram.Component
  alias Hologram.Runtime.PageDigestRegistry
  alias Hologram.Runtime.Templatable
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Renders the given DOM.

  ## Examples

      iex> dom = {:component, Module3, [{"id", [text: "my_component"]}], []}
      iex> render_dom(dom, %{}, [])
      {
        "<div>state_a = 1, state_b = 2</div>",
        %{"my_component" => %Component.Client{state: %{a: 1, b: 2}}}
      }
  """
  @spec render_dom(DOM.t(), %{(atom | {any, atom}) => any}, keyword(DOM.t())) ::
          {String.t(), %{atom => Component.Client.t()}}
  def render_dom(dom, context, slots)

  def render_dom(nodes, context, slots) when is_list(nodes) do
    nodes
    # There may be nil DOM nodes resulting from if blocks, e.g. {%if false}abc{/if}
    |> Enum.filter(& &1)
    |> Enum.reduce({"", %{}}, fn node, {acc_html, acc_clients} ->
      {html, clients} = render_dom(node, context, slots)
      {acc_html <> html, Map.merge(acc_clients, clients)}
    end)
  end

  def render_dom({:component, module, props_dom, children}, context, slots) do
    props_dom
    |> cast_props(module)
    |> inject_context_props(module, context)
    |> then(&{&1, Map.has_key?(&1, :id), expand_slots(children, slots)})
    |> then(fn
      {props, true, children} -> render_stateful_component(module, props, children, context)
      {props, false, children} -> render_stateless_component(module, props, children, context)
    end)
  end

  def render_dom({:element, "slot", _attrs, []}, context, slots) do
    render_dom(slots[:default], context, [])
  end

  def render_dom({:element, tag, attrs_dom, children}, context, slots) do
    children
    |> render_dom(context, slots)
    |> then(fn {children_html, children_clients} ->
      {render_atributes(attrs_dom), children_html, children_clients}
    end)
    |> then(fn {attrs_html, children_html, children_clients} ->
      tag
      |> then(fn
        tag when tag in @void_elems -> StringUtils.wrap(attrs_html, "<#{tag}", " />")
        tag -> StringUtils.wrap(children_html, "<#{tag}#{attrs_html}>", "</#{tag}>")
      end)
      |> then(&{&1, children_clients})
    end)
  end

  def render_dom({:expression, {value}}, _context, _slots) do
    {to_string(value), %{}}
  end

  def render_dom({:text, text}, _context, _slots) do
    {text, %{}}
  end

  # TODO: Refactor once there is something akin to {...@var} syntax
  # (it would be possible to pass page state as layout props this way).
  @doc """
  Renders the given page.

  ## Examples

      iex> render_page(MyPage, [{"param", [text: "value"]}], :my_persistent_term_key)
      {
        "<div>full page content including layout</div>",
        %{"page" => %Component.Client{state: %{a: 1, b: 2}}}
      }
  """
  @spec render_page(module, DOM.t()) :: {String.t(), %{atom => Component.Client.t()}}
  def render_page(page_module, params_dom) do
    layout_module = page_module.__layout_module__()
    params = cast_props(params_dom, page_module)

    page_module
    |> init_component(params)
    |> then(fn {initial_page_client, _server} -> initial_page_client end)
    |> then(&{&1, PageDigestRegistry.lookup(page_module)})
    |> then(fn {initial_page_client, page_digest} ->
      Templatable.put_context(initial_page_client, {Hologram.Runtime, :page_digest}, page_digest)
    end)
    |> render_page_initial(layout_module, page_module, params)
    |> render_page_final(page_module, params)
  end

  defp render_page_initial(initial_page_client, layout_module, page_module, params) do
    layout_props_dom = build_layout_props_dom(page_module, initial_page_client)

    params
    |> aggregate_vars(initial_page_client.state)
    |> then(&page_module.template().(&1))
    |> then(&{:component, layout_module, layout_props_dom, &1})
    |> render_dom(initial_page_client.context, [])
    |> then(fn {initial_html, initial_clients} ->
      {initial_html, initial_clients, initial_page_client}
    end)
  end

  defp render_page_final({html, clients, page_client}, page_module, params) do
    page_client
    |> Templatable.put_context({Hologram.Runtime, :page_mounted?}, true)
    |> then(&Map.put(clients, "page", &1))
    |> then(fn final_clients ->
      html
      |> inject_runtime("$INJECT_CLIENTS_DATA", final_clients)
      |> inject_runtime("$INJECT_PAGE_MODULE", page_module)
      |> inject_runtime("$INJECT_PAGE_PARAMS", params)
      |> then(&{&1, final_clients})
    end)
  end

  # Used both on the client and the server.
  defp aggregate_vars(props, state) do
    Map.merge(props, state)
  end

  # Used both on the client and the server.
  defp build_layout_props_dom(page_module, page_client) do
    page_module.__layout_props__()
    |> Enum.into(%{id: "layout"})
    |> aggregate_vars(page_client.state)
    |> Enum.map(fn {name, value} -> {to_string(name), [expression: {value}]} end)
  end

  defp cast_props(props_dom, module) do
    props_dom
    |> filter_allowed_props(module)
    |> Stream.map(&evaluate_prop_value/1)
    |> Stream.map(&normalize_prop_name/1)
    |> Enum.into(%{})
  end

  defp evaluate_prop_value({name, [expression: {value}]}) do
    {name, value}
  end

  defp evaluate_prop_value({name, value_parts}) do
    {text, _clients} = render_dom(value_parts, %{}, [])
    {name, text}
  end

  defp expand_slots(dom, slots)

  defp expand_slots(nodes, slots) when is_list(nodes) do
    Enum.map(nodes, &expand_slot(&1, slots))
  end

  defp expand_slot({:component, module, props, children}, slots) do
    {:component, module, props, expand_slots(children, slots)}
  end

  defp expand_slot({:element, "slot", _attrs, []}, slots) do
    slots[:default]
  end

  defp expand_slot({:element, tag, attrs, children}, slots) do
    {:element, tag, attrs, expand_slots(children, slots)}
  end

  defp expand_slot(node, _slots), do: node

  defp filter_allowed_props(props_dom, module) do
    module.__props__()
    |> Enum.reject(fn {_name, _type, opts} -> opts[:from_context] end)
    |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)
    |> then(&["id" | &1])
    |> then(&Enum.filter(props_dom, fn {name, _value_parts} -> name in &1 end))
  end

  defp init_component(module, props) do
    props
    |> module.init(%Component.Client{}, %Component.Server{})
    |> then(fn
      {client, server} -> {client, server}
      %Component.Client{} = client -> {client, %Component.Server{}}
      %Component.Server{} = server -> {%Component.Client{}, server}
    end)
  end

  defp inject_context_props(props_from_template, module, context) do
    Enum.reduce(module.__props__(), props_from_template, fn {name, _type, opts}, acc ->
      inject_context_prop({name, opts[:from_context]}, context, acc)
    end)
  end

  defp inject_context_prop({_name, nil}, _context, acc), do: acc

  defp inject_context_prop({name, from_context}, context, acc) do
    Map.put(acc, name, context[from_context])
  end

  defp inject_runtime(html, pattern, data) do
    data
    |> Encoder.encode_term()
    |> then(&String.replace(html, pattern, &1))
  end

  defp normalize_prop_name({name, value}) do
    {String.to_existing_atom(name), value}
  end

  defp render_attribute({name, []}), do: name

  defp render_attribute({name, value_parts}) do
    value_parts
    |> render_dom(%{}, [])
    |> then(fn {html, _clients} -> ~s(#{name}="#{html}") end)
  end

  defp render_atributes(attrs_dom)

  defp render_atributes([]), do: ""

  defp render_atributes(attrs_dom) do
    attrs_dom
    |> Enum.map_join(" ", &render_attribute/1)
    |> StringUtils.prepend(" ")
  end

  defp render_stateful_component(module, props, children, context) do
    module
    |> init_component(props)
    |> then(fn {client, _server} -> {client, aggregate_vars(props, client.state)} end)
    |> then(fn {client, vars} ->
      context
      |> Map.merge(client.context)
      |> then(&render_template(module, vars, children, &1))
      |> then(fn {html, children_clients} -> {html, children_clients, vars.id, client} end)
    end)
    |> then(fn {html, children_clients, vars_id, client} ->
      {html, Map.put(children_clients, vars_id, client)}
    end)
  end

  defp render_stateless_component(module, props, children, context) do
    # We need to run the default init/3 to determine
    # if it's actually a stateful component that is missing the `id` prop.
    empty_client_server_init_state = {%Component.Client{}, %Component.Server{}}

    module
    |> init_component(props)
    |> then(fn
      ^empty_client_server_init_state ->
        props
        |> aggregate_vars(%{})
        |> then(&render_template(module, &1, children, context))

      _stateful_component_with_id_missing ->
        raise Hologram.TemplateSyntaxError,
          message: "Stateful component #{module} is missing the 'id' property."
    end)
  end

  defp render_template(module, vars, children, context) do
    vars
    |> module.template().()
    |> render_dom(context, default: children)
  end
end
