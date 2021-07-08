defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler.{Context, Generator, Processor, Pruner}

  def build(module) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    Processor.compile(module)
    |> Pruner.prune()
    |> Enum.reduce("", fn {_, ir}, acc ->
      acc <> "\n" <> Generator.generate(ir, context)
    end)
  end
end
