defmodule Hologram.Template.ExpressionGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(ir) do
    # DEFER: pass actual %Context{} struct received from compiler
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    callback_return = Generator.generate(ir, context)
    "{ type: 'expression', callback: ($state) => { return #{callback_return} } }"
  end
end
