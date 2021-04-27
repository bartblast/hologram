defmodule Hologram.Transpiler.Builder do
  alias Hologram.Compiler
  alias Hologram.Transpiler.Eliminator
  alias Hologram.Transpiler.Generator

  def build(module) do
    Compiler.compile(module)
    |> Eliminator.eliminate(module)
    |> Enum.reduce("", fn {_, module_ast}, acc ->
      acc <> "\n" <> Generator.generate(module_ast)
    end)
  end
end
