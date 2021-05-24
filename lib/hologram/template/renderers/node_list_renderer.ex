defmodule Hologram.Template.NodeListRenderer do
  alias Hologram.Template.Renderer

  def render(nodes, state) do
    Enum.map(nodes, &Renderer.render(&1, state))
    |> Enum.join("")
  end
end
