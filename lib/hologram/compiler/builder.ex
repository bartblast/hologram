defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler
  alias Hologram.Compiler.Eliminator
  alias Hologram.Compiler.Generator

  def build(module) do
    Compiler.compile(module)
    |> Eliminator.eliminate(module)
    |> Enum.reduce("", fn {_, module_ast}, acc ->
      acc <> "\n" <> Generator.generate(module_ast)
    end)
  end
end
