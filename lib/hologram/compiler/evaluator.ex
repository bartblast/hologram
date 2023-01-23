defmodule Hologram.Compiler.Evaluator do
  alias Hologram.Compiler.IR

  def evaluate(%IR.AdditionOperator{left: left, right: right}) do
    evaluate(left) + evaluate(right)
  end

  def evaluate(%IR.IntegerType{value: value}), do: value
end
