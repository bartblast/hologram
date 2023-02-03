defmodule Hologram.Compiler.Evaluator do
  alias Hologram.Compiler.Detransformer

  def evaluate(ir) do
    ir
    |> Detransformer.detransform()
    |> Code.eval_quoted()
    |> elem(0)
  end
end
