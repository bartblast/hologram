defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Component
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Renders the given DOM node or DOM tree.
  """
  @spec render(DOM.dom_node() | DOM.tree()) :: {String.t(), %{atom => Component.Client.t()}}
  def render(node_or_tree)

  def render(nodes) when is_list(nodes) do
    Enum.reduce(nodes, {"", %{}}, fn node, {acc_html, acc_clients} ->
      {html, clients} = render(node)
      {acc_html <> html, Map.merge(acc_clients, clients)}
    end)
  end

  def render({:component, module, props, _children}) do
    if has_id_prop?(props) do
      render_stateful_component(module, props)
    else
      render_stateless_component(module, props)
    end
  end

  def render({:element, tag, attrs, children}) do
    attrs_html =
      if attrs != [] do
        attrs
        |> Enum.map_join(" ", fn {name, value_parts} ->
          {html, _clients} = render(value_parts)
          ~s(#{name}="#{html}")
        end)
        |> StringUtils.prepend(" ")
      else
        ""
      end

    {children_html, children_clients} = render(children)

    html =
      if tag in @void_elems do
        "<#{tag}#{attrs_html} />"
      else
        "<#{tag}#{attrs_html}>#{children_html}</#{tag}>"
      end

    {html, children_clients}
  end

  def render({:expression, {value}}) do
    {to_string(value), %{}}
  end

  def render({:text, text}) do
    {text, %{}}
  end

  defp aggregate_vars(props, state) do
    props
    |> Enum.map(fn {name, value_parts} ->
      {html, _clients} = render(value_parts)
      {String.to_existing_atom(name), html}
    end)
    |> Enum.into(%{})
    |> Map.merge(state)
  end

  defp has_id_prop?(props) do
    Enum.any?(props, fn {name, _value_parts} -> name == "id" end)
  end

  defp render_stateful_component(module, props) do
    init_result = module.init(props, %Component.Client{}, %Component.Server{})

    client =
      case init_result do
        {client, _server} ->
          client

        %Component.Client{} ->
          init_result

        %Component.Server{} ->
          %Component.Client{}
      end

    vars = aggregate_vars(props, client.state)

    {html, children_clients} =
      vars
      |> module.template.()
      |> render()

    clients = Map.put(children_clients, vars.id, client)

    {html, clients}
  end

  defp render_stateless_component(module, props) do
    props
    |> aggregate_vars(%{})
    |> module.template.()
    |> render()
  end
end
