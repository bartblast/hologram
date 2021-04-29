defmodule Hologram.Transpiler.DotOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(left, right) do
    "Kernel.dotOperator(#{Generator.generate(left)}, #{Generator.generate(right)})"
  end
end
