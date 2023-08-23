defmodule Hologram.Template.Renderer do
  alias Hologram.Template.VDOMTree

  @doc """
  Renders the given VDOM node or nodes.
  """
  @spec render(VDOMTree.vdom_node() | list(VDOMTree.vdom_node())) :: String.t()
  def render(node_or_nodes)

  def render(nodes) when is_list(nodes) do
    Enum.map(nodes, &render/1)
    |> Enum.join()
  end

  def render({:text, text}), do: text
end
