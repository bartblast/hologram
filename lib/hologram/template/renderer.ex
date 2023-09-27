defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Transformer
  alias Hologram.Component
  alias Hologram.Runtime.PageDigestLookup
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
    children = expand_slots(children, slots)

    props =
      props_dom
      |> cast_props(module)
      |> inject_context_props(module, context)

    if has_id_prop?(props) do
      render_stateful_component(module, props, children, context)
    else
      render_stateless_component(module, props, children, context)
    end
  end

  def render_dom({:element, "slot", _attrs, []}, context, slots) do
    render_dom(slots[:default], context, [])
  end

  def render_dom({:element, tag, attrs_dom, children}, context, slots) do
    attrs_html = render_atributes(attrs_dom)

    {children_html, children_clients} = render_dom(children, context, slots)

    html =
      if tag in @void_elems do
        "<#{tag}#{attrs_html} />"
      else
        "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
      end

    {html, children_clients}
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
  @spec render_page(module, DOM.t(), atom) :: {String.t(), %{atom => Component.Client.t()}}
  def render_page(page_module, params_dom, page_digest_lookup_store_key) do
    params = cast_props(params_dom, page_module)
    {initial_page_client, _server} = init_component(page_module, params)

    page_digest = PageDigestLookup.lookup(page_digest_lookup_store_key, page_module)

    %{context: page_context, state: page_state} =
      initial_page_client_with_injected_page_digest =
      Templatable.put_context(initial_page_client, {Hologram.Runtime, :page_digest}, page_digest)

    layout_module = page_module.__layout_module__()

    layout_props_dom =
      build_layout_props_dom(page_module, initial_page_client_with_injected_page_digest)

    vars = aggregate_vars(params, page_state)
    page_dom = page_module.template().(vars)
    layout_node = {:component, layout_module, layout_props_dom, page_dom}

    {initial_html, initial_clients} = render_dom(layout_node, page_context, [])

    final_page_client =
      Templatable.put_context(
        initial_page_client_with_injected_page_digest,
        {Hologram.Runtime, :initial_client_data_loaded?},
        true
      )

    final_clients = Map.put(initial_clients, "page", final_page_client)
    final_html = inject_runtime_bootstrap_data(initial_html, final_clients)

    {final_html, final_clients}
  end

  defp aggregate_vars(props, state) do
    Map.merge(props, state)
  end

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
    nodes
    |> Enum.map(&expand_slots(&1, slots))
    |> List.flatten()
  end

  defp expand_slots({:component, module, props, children}, slots) do
    {:component, module, props, expand_slots(children, slots)}
  end

  defp expand_slots({:element, "slot", _attrs, []}, slots) do
    slots[:default]
  end

  defp expand_slots({:element, tag, attrs, children}, slots) do
    {:element, tag, attrs, expand_slots(children, slots)}
  end

  defp expand_slots(node, _slots), do: node

  defp filter_allowed_props(props_dom, module) do
    registered_prop_names =
      module.__props__()
      |> Enum.reject(fn {_name, _type, opts} -> opts[:from_context] end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    allowed_props = ["id" | registered_prop_names]

    Enum.filter(props_dom, fn {name, _value_parts} -> name in allowed_props end)
  end

  defp has_id_prop?(props) do
    Enum.any?(props, fn {name, _value} -> name == :id end)
  end

  defp init_component(module, props) do
    init_result = module.init(props, %Component.Client{}, %Component.Server{})

    case init_result do
      {client, server} ->
        {client, server}

      %Component.Client{} = client ->
        {client, %Component.Server{}}

      %Component.Server{} = server ->
        {%Component.Client{}, server}
    end
  end

  defp inject_context_props(props_from_template, module, context) do
    props_from_context =
      module.__props__()
      |> Enum.filter(fn {_name, _type, opts} -> opts[:from_context] end)
      |> Enum.map(fn {name, _type, opts} -> {name, context[opts[:from_context]]} end)
      |> Enum.into(%{})

    Map.merge(props_from_template, props_from_context)
  end

  defp inject_runtime_bootstrap_data(html, clients) do
    data =
      clients
      |> Macro.escape()
      |> Normalizer.normalize()
      |> Transformer.transform(%Context{})
      |> Encoder.encode(%Context{})

    pattern = "window.__hologramRuntimeBootstrapData__ = \"...\";"

    replacement = """
    window.__hologramRuntimeBootstrapData__ = (typeClass) => {
      const Type = typeClass;
      return #{data};
    };\
    """

    String.replace(html, pattern, replacement)
  end

  defp normalize_prop_name({name, value}) do
    {String.to_existing_atom(name), value}
  end

  defp render_attribute(name, value_parts)

  defp render_attribute(name, []), do: name

  defp render_attribute(name, value_parts) do
    {html, _clients} = render_dom(value_parts, %{}, [])
    ~s(#{name}="#{html}")
  end

  defp render_atributes(attrs_dom)

  defp render_atributes([]), do: ""

  defp render_atributes(attrs_dom) do
    attrs_dom
    |> Enum.map_join(" ", fn {name, value_parts} ->
      render_attribute(name, value_parts)
    end)
    |> StringUtils.prepend(" ")
  end

  defp render_stateful_component(module, props, children, context) do
    {client, _server} = init_component(module, props)
    vars = aggregate_vars(props, client.state)
    context = Map.merge(context, client.context)

    {html, children_clients} = render_template(module, vars, children, context)
    clients = Map.put(children_clients, vars.id, client)

    {html, clients}
  end

  defp render_stateless_component(module, props, children, context) do
    # We need to run the default init/3 to determine
    # if it's actually a stateful component that is missing the `id` prop.
    {client, server} = init_component(module, props)

    if client != %Component.Client{} || server != %Component.Server{} do
      raise Hologram.TemplateSyntaxError,
        message: "Stateful component #{module} is missing the 'id' property."
    end

    vars = aggregate_vars(props, %{})

    render_template(module, vars, children, context)
  end

  defp render_template(module, vars, children, context) do
    vars
    |> module.template().()
    |> render_dom(context, default: children)
  end
end
