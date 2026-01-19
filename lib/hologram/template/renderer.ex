defmodule Hologram.Template.Renderer do
  @moduledoc false

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Commons.StringUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.Encoder
  alias Hologram.Component
  alias Hologram.Reflection
  alias Hologram.Server
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  defmodule Env do
    @moduledoc false

    defstruct context: %{}, node_type: nil, slots: [], tag_name: nil

    @type t :: %__MODULE__{
            context: %{(atom | {any, atom}) => any},
            node_type: :attribute | :element | :property | :public_comment | nil,
            slots: keyword(DOM.t()),
            tag_name: String.t() | nil
          }
  end

  @doc """
  Renders the given DOM.

  ## Examples

      iex> dom = {:component, MyModule, [{"cid", [text: "my_component"]}], []}
      iex> render_dom(dom, %Env{}, %Server{})
      {
        "<div>state_a = 1, state_b = 2</div>",
        %{"my_component" => %{module: MyModule, struct: %Component{state: %{a: 1, b: 2}}}},
        %Server{session: %{user_id: 123}}
      }
  """
  @spec render_dom(DOM.t(), Env.t(), Server.t()) ::
          {String.t(), %{String.t() => %{module: module, struct: Component.t()}}, Server.t()}
  def render_dom(dom, env, server_struct)

  def render_dom({:component, module, props_dom, children_dom}, env, server_struct) do
    expanded_children_dom = expand_slots(children_dom, env.slots)

    props =
      props_dom
      |> cast_props(module)
      |> inject_props_from_context(module, env.context)
      |> inject_default_prop_values(module)

    if has_cid_prop?(props) do
      render_stateful_component(module, props, expanded_children_dom, env.context, server_struct)
    else
      render_template(module, props, expanded_children_dom, env.context, server_struct)
    end
  end

  def render_dom({:doctype, content}, _env, server_struct) do
    {"<!DOCTYPE #{content}>", %{}, server_struct}
  end

  def render_dom({:element, "slot", _attrs_dom, []}, %Env{} = env, server_struct) do
    render_dom(env.slots[:default], %Env{env | slots: []}, server_struct)
  end

  def render_dom({:element, tag_name, attrs_dom, children_dom}, %Env{} = env, server_struct) do
    attrs_html = render_attributes(attrs_dom)

    children_env = %Env{env | node_type: :element, tag_name: tag_name}

    {children_html, component_registry, mutated_server_struct} =
      render_dom(children_dom, children_env, server_struct)

    html =
      if tag_name in @void_elems do
        "<#{tag_name}#{attrs_html} />"
      else
        "<#{tag_name}#{attrs_html}>#{children_html}</#{tag_name}>"
      end

    {html, component_registry, mutated_server_struct}
  end

  def render_dom({:expression, {value}}, _env, server_struct) do
    {stringify_for_interpolation(value), %{}, server_struct}
  end

  def render_dom({:public_comment, children_dom}, %Env{} = env, server_struct) do
    children_env = %Env{env | node_type: :public_comment}

    {children_html, component_registry, mutated_server_struct} =
      render_dom(children_dom, children_env, server_struct)

    html = "<!--#{children_html}-->"

    {html, component_registry, mutated_server_struct}
  end

  def render_dom({:text, text}, %Env{tag_name: "script"}, server_struct) do
    {text, %{}, server_struct}
  end

  def render_dom({:text, text}, _env, server_struct) do
    {HtmlEntities.encode(text), %{}, server_struct}
  end

  def render_dom(nodes, env, server_struct) when is_list(nodes) do
    nodes
    # There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if}
    |> Enum.filter(& &1)
    |> Enum.reduce({"", %{}, server_struct}, fn node,
                                                {acc_html, acc_component_registry,
                                                 acc_server_struct} ->
      {html, component_registry, mutated_server_struct} = render_dom(node, env, acc_server_struct)

      {acc_html <> html, Map.merge(acc_component_registry, component_registry),
       mutated_server_struct}
    end)
  end

  # TODO: Refactor once there is something akin to {...@vars} syntax
  # (it would be possible to pass page state as layout props this way).
  @doc """
  Renders the given page.

  ## Examples

      iex> render_page(MyPage, %{param: "value"}, %Server{}, initial_page?: true)
      {
        "<div>full page content including layout</div>",
        %{"page" => %{module: MyPage, struct: %Component{state: %{a: 1, b: 2}}}},
        %Server{session: %{user_id: 123}}
      }
  """
  @spec render_page(module, %{atom => any}, Server.t(), T.opts()) ::
          {String.t(), %{String.t() => %{module: module, struct: Component.t()}}, Server.t()}
  def render_page(page_module, params, server_struct, opts) do
    initial_page? = opts[:initial_page?] || false

    {page_component_struct, page_server_struct} =
      init_component(page_module, params, server_struct)

    page_digest = PageDigestRegistry.lookup(page_module)

    page_component_struct_with_emitted_context_before_rendering =
      page_component_struct
      |> put_initial_page_flag_context(initial_page?)
      |> put_page_digest_context(page_digest)
      |> put_page_mounted_flag_context(false)
      |> maybe_put_csrf_token_context(opts, initial_page?)

    {initial_html, initial_component_registry, final_server_struct} =
      render_page_inside_layout(
        page_module,
        params,
        page_component_struct_with_emitted_context_before_rendering,
        page_server_struct
      )

    page_component_struct_with_emitted_context_after_rendering =
      page_component_struct_with_emitted_context_before_rendering
      |> put_initial_page_flag_context(false)
      |> put_page_mounted_flag_context(true)

    component_registry_with_page_struct =
      Map.put(
        initial_component_registry,
        "page",
        %{module: page_module, struct: page_component_struct_with_emitted_context_after_rendering}
      )

    html_with_interpolated_js =
      initial_html
      |> interpolate_asset_manifest_js()
      |> interpolate_component_registry_js(component_registry_with_page_struct)
      |> interpolate_page_module_js(page_module)
      |> interpolate_page_params_js(params)

    {html_with_interpolated_js, component_registry_with_page_struct, final_server_struct}
  end

  @doc """
  Converts a value to a string for safe interpolation in HTML templates.
  Always HTML-escapes the output to prevent XSS.

  ## Examples

      iex> stringify_for_interpolation("hello")
      "hello"

      iex> stringify_for_interpolation("<script>")
      "&lt;script&gt;"
  """
  @spec stringify_for_interpolation(any) :: String.t()
  def stringify_for_interpolation(value) do
    value
    |> to_string()
    |> HtmlEntities.encode()
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

  defp evaluate_prop_value({name, [expression: value]}) do
    {name, value}
  end

  defp evaluate_prop_value({name, value_dom}) do
    {value_str, %{}, _server_struct} =
      render_dom(value_dom, %Env{node_type: :property}, %Server{})

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

  defp init_component(module, props, server_struct) do
    init_result =
      if Reflection.has_function?(module, :init, 3) do
        module.init(props, %Component{}, server_struct)
      else
        {%Component{}, server_struct}
      end

    case init_result do
      {component_struct, mutaded_server_struct} ->
        {component_struct, mutaded_server_struct}

      %Component{} = component_struct ->
        {component_struct, server_struct}

      %Server{} = mutated_server_struct ->
        {%Component{}, mutated_server_struct}
    end
  end

  defp inject_default_prop_values(props, module) do
    Enum.reduce(module.__props__(), props, fn {name, _type, opts}, acc ->
      if !Map.has_key?(acc, name) && Keyword.has_key?(opts, :default) do
        Map.put(acc, name, Keyword.get(opts, :default))
      else
        acc
      end
    end)
  end

  defp inject_props_from_context(props, module, context) do
    props_from_context =
      module.__props__()
      |> Enum.filter(fn {_name, _type, opts} ->
        opts[:from_context] && Map.has_key?(context, opts[:from_context])
      end)
      |> Enum.map(fn {name, _type, opts} -> {name, context[opts[:from_context]]} end)
      |> Enum.into(%{})

    Map.merge(props, props_from_context)
  end

  defp interpolate_asset_manifest_js(html) do
    asset_manifest_js = AssetManifestCache.get_manifest_js()
    String.replace(html, "$ASSET_MANIFEST_JS_PLACEHOLDER", asset_manifest_js)
  end

  defp interpolate_component_registry_js(html, component_registry) do
    component_registry_js = Encoder.encode_term!(component_registry)
    String.replace(html, "$COMPONENT_REGISTRY_JS_PLACEHOLDER", component_registry_js)
  end

  defp interpolate_page_module_js(html, page_module) do
    page_module_js = Encoder.encode_term!(page_module)
    String.replace(html, "$PAGE_MODULE_JS_PLACEHOLDER", page_module_js)
  end

  defp interpolate_page_params_js(html, page_params) do
    page_params_js = Encoder.encode_term!(page_params)
    String.replace(html, "$PAGE_PARAMS_JS_PLACEHOLDER", page_params_js)
  end

  defp maybe_put_csrf_token_context(page_component_struct, opts, true) do
    csrf_token =
      opts[:csrf_token] || raise ArgumentError, "CSRF token is required for initial page requests"

    Component.put_context(
      page_component_struct,
      {Hologram.Runtime, :csrf_token},
      csrf_token
    )
  end

  defp maybe_put_csrf_token_context(page_component_struct, _opts, false) do
    page_component_struct
  end

  defp normalize_prop_name({name, value}) do
    {String.to_existing_atom(name), value}
  end

  defp put_initial_page_flag_context(page_component_struct, initial_page?) do
    Component.put_context(
      page_component_struct,
      {Hologram.Runtime, :initial_page?},
      initial_page?
    )
  end

  defp put_page_digest_context(page_component_struct, page_digest) do
    Component.put_context(
      page_component_struct,
      {Hologram.Runtime, :page_digest},
      page_digest
    )
  end

  defp put_page_mounted_flag_context(page_component_struct, page_mounted?) do
    Component.put_context(
      page_component_struct,
      {Hologram.Runtime, :page_mounted?},
      page_mounted?
    )
  end

  defp render_attribute(name, value_dom)

  defp render_attribute(name, []), do: name

  defp render_attribute(_name, expression: {nil}), do: ""

  defp render_attribute(_name, expression: {false}), do: ""

  defp render_attribute(name, value_dom) do
    {value_str, %{}, _server_struct} =
      render_dom(value_dom, %Env{node_type: :attribute}, %Server{})

    if value_str == "" do
      name
    else
      ~s(#{name}="#{value_str}")
    end
  end

  defp render_attributes(attrs_dom)

  defp render_attributes([]), do: ""

  defp render_attributes(attrs_dom) do
    attrs_dom
    |> Enum.reject(fn {name, _value_dom} -> String.starts_with?(name, "$") end)
    |> Enum.map(fn {name, value_dom} -> render_attribute(name, value_dom) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> StringUtils.prepend_if_not_empty(" ")
  end

  defp render_page_inside_layout(
         page_module,
         params,
         %{
           emitted_context: page_emitted_context,
           state: page_state
         },
         server_struct
       ) do
    vars = Map.merge(params, page_state)
    page_dom = page_module.template().(vars)

    layout_module = page_module.__layout_module__()
    layout_props_dom = build_layout_props_dom(page_module, page_state)
    layout_node = {:component, layout_module, layout_props_dom, page_dom}

    render_dom(layout_node, %Env{context: page_emitted_context}, server_struct)
  end

  defp render_stateful_component(module, props, children_dom, context, server_struct) do
    {component_struct, mutated_server_struct} = init_component(module, props, server_struct)
    vars = Map.merge(props, component_struct.state)
    merged_context = Map.merge(context, component_struct.emitted_context)

    {html, children_component_registry, final_server_struct} =
      render_template(module, vars, children_dom, merged_context, mutated_server_struct)

    component_registry =
      Map.put(children_component_registry, vars.cid, %{module: module, struct: component_struct})

    {html, component_registry, final_server_struct}
  end

  defp render_template(module, vars, children_dom, context, server_struct) do
    vars
    |> module.template().()
    |> render_dom(%Env{context: context, slots: [default: children_dom]}, server_struct)
  end
end
