defmodule Hologram.Transpiler.DotOperatorGenerator do
  alias Hologram.Transpiler.Generator

  def generate(left, right) do
    "Kernel.dot_operator(#{Generator.generate(left)}, #{Generator.generate(right)})"
  end
end
