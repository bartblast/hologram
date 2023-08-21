defmodule Hologram.Template.Renderer do
  def render(node_or_nodes)

  def render({:text, text}), do: text
end
