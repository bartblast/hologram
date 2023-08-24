defmodule Hologram.Template.Renderer do
  alias Hologram.Commons.StringUtils
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

  def render({:element, tag, attrs, children}) do
    attrs_html =
      if attrs != [] do
        Enum.map_join(attrs, " ", fn {name, value_parts} ->
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
end
