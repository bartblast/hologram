alias Hologram.Compiler.{Context, Opts}
alias Hologram.Compiler.JSEncoder
alias Hologram.Template.VDOM.Expression
alias Hologram.Template.Encoder

defimpl Encoder, for: Expression do
  def encode(%{ir: ir}) do
    # DEFER: pass actual %Context{} struct received from compiler
    callback_return = JSEncoder.encode(ir, %Context{}, %Opts{template: true})

    "{ type: 'expression', callback: ($bindings) => { return #{callback_return} } }"
  end
end
