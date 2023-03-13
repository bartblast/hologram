alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.UnaryNegativeOperator

defimpl JSEncoder, for: UnaryNegativeOperator do
  def encode(%{value: value}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(value, context, opts)
    "Hologram.Interpreter.$unary_negative_operator(#{value})"
  end
end
