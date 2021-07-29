defmodule Hologram.Template.ExpressionGenerator do
  alias Hologram.Compiler.{Context, Generator}

  def generate(ir) do
    # TODO: pass actual %Context{} struct received from
    callback_return = Generator.generate(ir, %Context{})
    
    "{ type: 'expression', callback: ($state) => { return #{callback_return} } }"
  end
end
