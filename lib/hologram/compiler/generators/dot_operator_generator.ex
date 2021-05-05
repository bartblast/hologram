defmodule Hologram.Compiler.DotOperatorGenerator do
  alias Hologram.Compiler.Generator

  def generate(left, right, context) do
    "Kernel.dotOperator(#{Generator.generate(left, context)}, #{Generator.generate(right, context)})"
  end
end
