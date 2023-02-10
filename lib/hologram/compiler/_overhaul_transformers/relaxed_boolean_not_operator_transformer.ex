defmodule Hologram.Compiler.RelaxedBooleanNotOperatorTransformer do
  alias Hologram.Compiler.IR.RelaxedBooleanNotOperator
  alias Hologram.Compiler.Transformer

  def transform({:__block__, _, [{:!, _, [value]}]}) do
    build_ir(value)
  end

  def transform({:!, _, [value]}) do
    build_ir(value)
  end

  defp build_ir(value) do
    %RelaxedBooleanNotOperator{
      value: Transformer.transform(value)
    }
  end
end
