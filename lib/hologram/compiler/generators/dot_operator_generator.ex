defmodule Hologram.Compiler.DotOperatorGenerator do
  alias Hologram.Compiler.{Context, Generator, Helpers, Opts}

  def generate(left, right, %Context{} = context, %Opts{} = opts) do
    left = Generator.generate(left, context, opts)
    right = Generator.generate(right, context, opts)
    class_name = Helpers.class_name(Kernel.SpecialForms)

    "#{class_name}.$dot(#{left}, #{right})"
  end
end
