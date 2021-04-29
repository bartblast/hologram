defmodule Hologram.Transpiler.AdditionOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(left, right) do
    "Kernel.additionOperator(#{Generator.generate(left)}, #{Generator.generate(right)})"
  end
end
