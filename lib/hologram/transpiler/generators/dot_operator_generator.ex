defmodule Hologram.Transpiler.DotOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(left, right, context) do
    "Kernel.dotOperator(#{Generator.generate(left, context)}, #{Generator.generate(right, context)})"
  end
end
