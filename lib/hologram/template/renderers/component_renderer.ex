defmodule Hologram.Template.ComponentRenderer do
  alias Hologram.Template.{Parser, Renderer, Transformer}

  def render(module, state) do
    module.template()
    |> Parser.parse!()
    |> Transformer.transform()
    |> Renderer.render(state)
  end
end
