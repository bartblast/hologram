defmodule Hologram.Compiler.AdditionOperatorGenerator do
  alias Hologram.Compiler.{Context, Generator, Helpers}

  def generate(left, right, %Context{} = context) do
    left = Generator.generate(left, context)
    right = Generator.generate(right, context)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$add(#{left}, #{right})"
  end
end
