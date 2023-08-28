defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Component
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Renders the given DOM node or DOM tree.
  """
  @spec render(DOM.dom_node() | DOM.tree(), keyword(DOM.tree())) ::
          {String.t(), %{atom => Component.Client.t()}}
  def render(node_or_tree, slots)

  def render(nodes, slots) when is_list(nodes) do
    Enum.reduce(nodes, {"", %{}}, fn node, {acc_html, acc_clients} ->
      {html, clients} = render(node, slots)
      {acc_html <> html, Map.merge(acc_clients, clients)}
    end)
  end

  def render({:component, module, props, children}, _slots) do
    if has_id_prop?(props) do
      render_stateful_component(module, props, children)
    else
      render_stateless_component(module, props, children)
    end
  end

  def render({:element, "slot", _attrs, []}, slots) do
    render(slots[:default], [])
  end

  def render({:element, tag, attrs, children}, slots) do
    attrs_html =
      if attrs != [] do
        attrs
        |> Enum.map_join(" ", fn {name, value_parts} ->
          {html, _clients} = render(value_parts, [])
          ~s(#{name}="#{html}")
        end)
        |> StringUtils.prepend(" ")
      else
        ""
      end

    {children_html, children_clients} = render(children, slots)

    html =
      if tag in @void_elems do
        "<#{tag}#{attrs_html} />"
      else
        "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
      end

    {html, children_clients}
  end

  def render({:expression, {value}}, _slots) do
    {to_string(value), %{}}
  end

  def render({:text, text}, _slots) do
    {text, %{}}
  end

  defp aggregate_vars(props, state) do
    props
    |> Enum.map(fn {name, value_parts} ->
      {html, _clients} = render(value_parts, [])
      {String.to_existing_atom(name), html}
    end)
    |> Enum.into(%{})
    |> Map.merge(state)
  end

  defp has_id_prop?(props) do
    Enum.any?(props, fn {name, _value_parts} -> name == "id" end)
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

  defp render_stateful_component(module, props, children) do
    {client, _server} = init_component(module, props)
    vars = aggregate_vars(props, client.state)

    {html, children_clients} =
      vars
      |> module.template.()
      |> render(default: children)

    clients = Map.put(children_clients, vars.id, client)

    {html, clients}
  end

  defp render_stateless_component(module, props, children) do
    {client, server} = init_component(module, props)

    if client != %Component.Client{} || server != %Component.Server{} do
      raise Hologram.Template.SyntaxError,
        message: "Stateful component #{module} is missing the 'id' property."
    end

    props
    |> aggregate_vars(%{})
    |> module.template.()
    |> render(default: children)
  end
end
