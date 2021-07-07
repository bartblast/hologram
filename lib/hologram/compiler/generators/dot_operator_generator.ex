defmodule Hologram.Compiler.DotOperatorGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(left, right, %Context{} = context) do
    left = Generator.generate(left, context)
    right = Generator.generate(right, context)

    "Kernel.$dot(#{left}, #{right})"
  end
end
