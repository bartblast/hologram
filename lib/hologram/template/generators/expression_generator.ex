defmodule Hologram.Template.ExpressionGenerator do
  alias Hologram.Compiler.Generator

  def generate(ir, context) do
    callback_return = Generator.generate(ir, context, [])
    "{ type: 'expression', callback: ($state) => { return #{callback_return} } }"
  end
end
