defmodule Hologram.Compiler.RelaxedBooleanNotOperatorTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.RelaxedBooleanNotOperator

  def transform({:__block__, _, [{:!, _, [value]}]}, %Context{} = context) do
    build_ir(value, context)
  end

  def transform({:!, _, [value]}, %Context{} = context) do
    build_ir(value, context)
  end

  defp build_ir(value, context) do
    %RelaxedBooleanNotOperator{
      value: Transformer.transform(value, context)
    }
  end
end
