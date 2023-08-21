defmodule Hologram.Template.Renderer do
  alias Hologram.Template.VDOMTree

  @doc """
  Renders the given VDOM node or nodes.
  """
  @spec render(VDOMTree.vdom_node() | list(VDOMTree.vdom_node())) :: String.t()
  def render(node_or_nodes)

  def render({:text, text}), do: text
end
