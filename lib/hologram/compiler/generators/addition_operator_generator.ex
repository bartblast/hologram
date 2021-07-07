defmodule Hologram.Compiler.AdditionOperatorGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(left, right, %Context{} = context) do
    left = Generator.generate(left, context, [])
    right = Generator.generate(right, context, [])

    "Kernel.$add(#{left}, #{right})"
  end
end
