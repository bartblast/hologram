defmodule Hologram.Template.Builder do
  alias Hologram.Compiler.{Helpers, Processor}
  alias Hologram.Template.{Parser, Transformer}
  
  def build(module) do
    aliases =
      Helpers.module_name_segments(module)
      |> Processor.get_module_definition()
      |> Map.get(:aliases)

    module.template()
    |> Parser.parse!()
    |> Transformer.transform(aliases)
  end
end
