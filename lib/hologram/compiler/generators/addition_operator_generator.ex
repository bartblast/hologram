defmodule Hologram.Compiler.AdditionOperatorGenerator do
  alias Hologram.Compiler.Generator

  def generate(left, right, context) do
    "Kernel.additionOperator(#{Generator.generate(left, context)}, #{Generator.generate(right, context)})"
  end
end
