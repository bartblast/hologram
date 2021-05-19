defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Generator, Processor, Pruner}

  def build(module) do
    Processor.compile(module)
    |> Pruner.prune(module)
    |> Enum.reduce("", fn {_, ast}, acc ->
      acc <> "\n" <> Generator.generate(ast)
    end)
  end
end
