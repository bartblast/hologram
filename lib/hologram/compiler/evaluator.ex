defmodule Hologram.Compiler.Evaluator do
  alias Hologram.Compiler.IR

  def evaluate(%IR.IntegerType{value: value}), do: value
end
