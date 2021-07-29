defmodule Hologram.Template.ComponentRenderer do
  alias Hologram.Template.{Builder, Renderer}

  def render(module, state) do
    Builder.build(module)
    |> Renderer.render(state)
  end
end
