defmodule Hologram.Template.ExpressionGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(ir) do
    # TODO: pass actual %Context{} struct received from compiler
    context = %Context{module: nil, uses: [], imports: [], aliases: [], attributes: []}

    tuple_first_elem_ir = hd(ir.data)
    callback_return = Generator.generate(tuple_first_elem_ir, context)
    "{ type: 'expression', callback: ($state) => { return #{callback_return} } }"
  end
end
