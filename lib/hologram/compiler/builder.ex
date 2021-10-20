defmodule Hologram.Compiler.Builder do
  alias Hologram.Compiler
  alias Hologram.Compiler.{Context, Encoder, Opts, Pruner}

  def build(module) do
    Compiler.compile(module)
    |> Pruner.prune(module)
    |> Enum.reduce("", fn {_, ir}, acc ->
      # TODO: pass actual %Context{} struct received from compiler
      acc <> "\n" <> Encoder.encode(ir, %Context{}, %Opts{})
    end)
  end
end
