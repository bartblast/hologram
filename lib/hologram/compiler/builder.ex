defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Generator, Processor, Pruner}

  def build(module) do
    Processor.compile(module)
    |> Pruner.prune()
    |> Enum.reduce("", fn {_, ir}, acc ->
      acc <> "\n" <> Generator.generate(ir)
    end)
  end
end
