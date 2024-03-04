defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.Encoder
  alias Hologram.Component
  alias Hologram.Runtime.PageDigestRegistry
  alias Hologram.Runtime.Templatable
  alias Hologram.Server
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Renders the given DOM.

  ## Examples

      iex> dom = {:component, Module3, [{"cid", [text: "my_component"]}], []}
      iex> render_dom(dom, %{}, [])
      {
        "<div>state_a = 1, state_b = 2</div>",
        %{"my_component" => %Component{state: %{a: 1, b: 2}}}
      }
  """
  @spec render_dom(DOM.t(), %{(atom | {any, atom}) => any}, keyword(DOM.t())) ::
          {String.t(), %{atom => Component.t()}}
  def render_dom(dom, context, slots)

  def render_dom({:component, module, props_dom, children_dom}, context, slots) do
    expanded_children_dom = expand_slots(children_dom, slots)

    props =
      props_dom
      |> cast_props(module)
      |> inject_props_from_context(module, context)

    if has_cid_prop?(props) do
      render_stateful_component(module, props, expanded_children_dom, context)
    else
      render_template(module, props, expanded_children_dom, context)
    end
  end

  def render_dom({:element, "slot", _attrs_dom, []}, context, slots) do
    render_dom(slots[:default], context, [])
  end

  def render_dom({:element, tag_name, attrs_dom, children_dom}, context, slots) do
    attrs_html = render_attributes(attrs_dom)

    {children_html, component_structs} = render_dom(children_dom, context, slots)

    html =
      if tag_name in @void_elems do
        "<#{tag_name}#{attrs_html} />"
      else
        "<#{tag_name}#{attrs_html}>#{children_html}</#{tag_name}>"
      end

    {html, component_structs}
  end

  def render_dom({:expression, {value}}, _context, _slots) do
    {to_string(value), %{}}
  end

  def render_dom({:text, text}, _context, _slots) do
    {text, %{}}
  end

  def render_dom(nodes, context, slots) when is_list(nodes) do
    nodes
    # There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if}
    |> Enum.filter(& &1)
    |> Enum.reduce({"", %{}}, fn node, {acc_html, acc_component_structs} ->
      {html, component_struct} = render_dom(node, context, slots)
      {acc_html <> html, Map.merge(acc_component_structs, component_struct)}
    end)
  end

  # TODO: Refactor once there is something akin to {...@vars} syntax
  # (it would be possible to pass page state as layout props this way).
  @doc """
  Renders the given page.

  ## Examples

      iex> render_page(MyPage, [{"param", [text: "value"]}], initial_page?: true)
      {
        "<div>full page content including layout</div>",
        %{"page" => %Component{state: %{a: 1, b: 2}}}
      }
  """
  @spec render_page(module, DOM.t(), keyword()) :: {String.t(), %{atom => Component.t()}}
  def render_page(page_module, params_dom, opts) do
    initial_page? = opts[:initial_page?] || false
    params = cast_props(params_dom, page_module)
    {page_component_struct, _server_struct} = init_component(page_module, params)

    page_digest = PageDigestRegistry.lookup(page_module)

    page_component_struct_with_emitted_context_before_rendering =
      page_component_struct
      |> put_initial_page_flag_context(initial_page?)
      |> put_page_digest_context(page_digest)
      |> put_page_mounted_flag_context(false)

    {initial_html, initial_component_structs} =
      render_page_inside_layout(
        page_module,
        params,
        page_component_struct_with_emitted_context_before_rendering
      )

    page_component_struct_with_emitted_context_after_rendering =
      page_component_struct_with_emitted_context_before_rendering
      |> put_initial_page_flag_context(false)
      |> put_page_mounted_flag_context(true)

    component_structs_with_page_struct =
      Map.put(
        initial_component_structs,
        "page",
        page_component_struct_with_emitted_context_after_rendering
      )

    html_with_interpolated_js =
      initial_html
      |> interpolate_component_structs_js(component_structs_with_page_struct)
      |> interpolate_page_module_js(page_module)
      |> interpolate_page_params_js(params)

    {html_with_interpolated_js, component_structs_with_page_struct}
  end

  defp build_layout_props_dom(page_module, page_state) do
    page_module.__layout_props__()
    |> Enum.into(%{cid: "layout"})
    |> Map.merge(page_state)
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

  defp evaluate_prop_value({name, value_dom}) do
    {value_str, %{}} = render_dom(value_dom, %{}, [])
    {name, value_str}
  end

  defp expand_slots(dom, slots)

  defp expand_slots(nodes, slots) when is_list(nodes) do
    nodes
    |> Enum.map(&expand_slots(&1, slots))
    |> List.flatten()
  end

  defp expand_slots({:component, module, props_dom, children_dom}, slots) do
    {:component, module, props_dom, expand_slots(children_dom, slots)}
  end

  defp expand_slots({:element, "slot", _attrs_dom, []}, slots) do
    slots[:default]
  end

  defp expand_slots({:element, tag_name, attrs_dom, children_dom}, slots) do
    {:element, tag_name, attrs_dom, expand_slots(children_dom, slots)}
  end

  defp expand_slots(node, _slots), do: node

  defp filter_allowed_props(props_dom, module) do
    registered_prop_names =
      module.__props__()
      |> Enum.reject(fn {_name, _type, opts} -> opts[:from_context] end)
      |> Enum.map(fn {name, _type, _opts} -> to_string(name) end)

    allowed_prop_names = ["cid" | registered_prop_names]

    Enum.filter(props_dom, fn {name, _value_dom} -> name in allowed_prop_names end)
  end

  defp has_cid_prop?(props) do
    Enum.any?(props, fn {name, _value} -> name == :cid end)
  end

  defp init_component(module, props) do
    init_result =
      if function_exported?(module, :init, 3) do
        module.init(props, %Component{}, %Server{})
      else
        {%Component{}, %Server{}}
      end

    case init_result do
      {component, server} ->
        {component, server}

      %Component{} = component ->
        {component, %Server{}}

      %Server{} = server ->
        {%Component{}, server}
    end
  end

  defp inject_props_from_context(props_from_template, module, context) do
    props_from_context =
      module.__props__()
      |> Enum.filter(fn {_name, _type, opts} -> opts[:from_context] end)
      |> Enum.map(fn {name, _type, opts} -> {name, context[opts[:from_context]]} end)
      |> Enum.into(%{})

    Map.merge(props_from_template, props_from_context)
  end

  defp interpolate_component_structs_js(html, component_structs) do
    component_structs_js = Encoder.encode_term(component_structs)
    String.replace(html, "$COMPONENT_STRUCTS_JS_PLACEHOLDER", component_structs_js)
  end

  defp interpolate_page_module_js(html, page_module) do
    page_module_js = Encoder.encode_term(page_module)
    String.replace(html, "$PAGE_MODULE_JS_PLACEHOLDER", page_module_js)
  end

  defp interpolate_page_params_js(html, page_params) do
    page_params_js = Encoder.encode_term(page_params)
    String.replace(html, "$PAGE_PARAMS_JS_PLACEHOLDER", page_params_js)
  end

  defp normalize_prop_name({name, value}) do
    {String.to_existing_atom(name), value}
  end

  defp put_initial_page_flag_context(page_component_struct, initial_page?) do
    Templatable.put_context(
      page_component_struct,
      {Hologram.Runtime, :initial_page?},
      initial_page?
    )
  end

  defp put_page_digest_context(page_component_struct, page_digest) do
    Templatable.put_context(
      page_component_struct,
      {Hologram.Runtime, :page_digest},
      page_digest
    )
  end

  defp put_page_mounted_flag_context(page_component_struct, page_mounted?) do
    Templatable.put_context(
      page_component_struct,
      {Hologram.Runtime, :page_mounted?},
      page_mounted?
    )
  end

  defp render_attribute(name, value_dom)

  defp render_attribute(name, []), do: name

  defp render_attribute(name, value_dom) do
    {value_str, %{}} = render_dom(value_dom, %{}, [])
    ~s(#{name}="#{value_str}")
  end

  defp render_attributes(attrs_dom)

  defp render_attributes([]), do: ""

  defp render_attributes(attrs_dom) do
    attrs_dom
    |> Enum.map_join(" ", fn {name, value_dom} ->
      render_attribute(name, value_dom)
    end)
    |> StringUtils.prepend(" ")
  end

  defp render_page_inside_layout(page_module, params, %{context: page_context, state: page_state}) do
    vars = Map.merge(params, page_state)
    page_dom = page_module.template().(vars)

    layout_module = page_module.__layout_module__()
    layout_props_dom = build_layout_props_dom(page_module, page_state)
    layout_node = {:component, layout_module, layout_props_dom, page_dom}

    render_dom(layout_node, page_context, [])
  end

  defp render_stateful_component(module, props, children_dom, context) do
    {component_struct, _server_struct} = init_component(module, props)
    vars = Map.merge(props, component_struct.state)
    merged_context = Map.merge(context, component_struct.context)

    {html, children_component_structs} =
      render_template(module, vars, children_dom, merged_context)

    component_structs = Map.put(children_component_structs, vars.cid, component_struct)

    {html, component_structs}
  end

  defp render_template(module, vars, children_dom, context) do
    vars
    |> module.template().()
    |> render_dom(context, default: children_dom)
  end
end
