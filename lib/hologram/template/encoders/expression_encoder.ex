alias Hologram.Compiler.{Context, Opts}
alias Hologram.Compiler.Encoder, as: CompilerEncoder
alias Hologram.Template.Document.Expression
alias Hologram.Template.Encoder

defimpl Encoder, for: Expression do
  def encode(%{ir: ir}) do
    # DEFER: pass actual %Context{} struct received from compiler
    callback_return = CompilerEncoder.encode(ir, %Context{}, %Opts{template: true})

    "{ type: 'expression', callback: ($state) => { return #{callback_return} } }"
  end
end
