defmodule Hologram.Template.Renderer do
  alias Hologram.Template.DOM

  @doc """
  Renders the given DOM node or DOM tree.
  """
  @spec render(DOM.dom_node() | DOM.tree()) :: String.t()
  def render(node_or_tree)

  def render(nodes) when is_list(nodes) do
    Enum.map(nodes, &render/1)
    |> Enum.join()
  end

  def render({:text, text}), do: text
end
