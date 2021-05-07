defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.Eliminator
  alias Hologram.Compiler.Generator
  alias Hologram.Compiler.Processor

  def build(module) do
    Processor.compile(module)
    |> Eliminator.eliminate(module)
    |> Enum.reduce("", fn {_, ast}, acc ->
      acc <> "\n" <> Generator.generate(ast)
    end)
  end
end
