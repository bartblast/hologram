defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
  alias Hologram.Component
  alias Hologram.Template.DOM

  # https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems ~w(area base br col embed hr img input link meta param source track wbr)

  @doc """
  Renders the given DOM node or DOM tree.
  """
  @spec render(DOM.dom_node() | DOM.tree()) :: String.t()
  def render(node_or_tree)

  def render(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &render/1)
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
          ~s(#{name}="#{render(value_parts)}")
        end)
        |> StringUtils.prepend(" ")
      else
        ""
      end

    if tag in @void_elems do
      "<#{tag}#{attrs_html} />"
    else
      "<#{tag}#{attrs_html}>#{render(children)}</#{tag}>"
    end
  end

  def render({:expression, {value}}), do: to_string(value)

  def render({:text, text}), do: text

  defp aggregate_vars(props, state) do
    props
    |> Enum.map(fn {name, value_parts} ->
      {String.to_existing_atom(name), render(value_parts)}
    end)
    |> Enum.into(%{})
    |> Map.merge(state)
  end

  defp has_id_prop?(props) do
    Enum.any?(props, fn {name, _value_parts} -> name == "id" end)
  end

  defp render_stateful_component(module, props) do
    init_result = module.init(props, %Component.Client{}, %Component.Server{})

    state =
      case init_result do
        {%{state: state} = _client, _server} ->
          state

        %{state: state} ->
          state

        _fallback ->
          %{}
      end

    props
    |> aggregate_vars(state)
    |> module.template.()
    |> render()
  end

  defp render_stateless_component(module, props) do
    props
    |> aggregate_vars(%{})
    |> module.template.()
    |> render()
  end
end
