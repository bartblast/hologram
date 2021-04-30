defmodule Hologram.Transpiler.AdditionOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(left, right, context) do
    "Kernel.additionOperator(#{Generator.generate(left, context)}, #{Generator.generate(right, context)})"
  end
end
