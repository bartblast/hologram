defmodule Hologram.Template.Renderer do
  alias Hologram.Template.DOM

  @doc """
  Renders the given DOM node or DOM tree.
  """
  @spec render(DOM.dom_node() | DOM.tree()) :: String.t()
  def render(node_or_tree)

  def render(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &render/1)
  end

  def render({:expression, {value}}), do: to_string(value)

  def render({:text, text}), do: text
end
