alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.UnaryPositiveOperator

defimpl JSEncoder, for: UnaryPositiveOperator do
  def encode(%{value: value}, %Context{} = context, %Opts{} = opts) do
    JSEncoder.encode(value, context, opts)
  end
end
