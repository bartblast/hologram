alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.UnaryNegativeOperator

defimpl JSEncoder, for: UnaryNegativeOperator do
  def encode(%{value: value_ir}, %Context{} = context, %Opts{} = opts) do
    value_ir = Map.put(value_ir, :value, -value_ir.value)
    JSEncoder.encode(value_ir, context, opts)
  end
end
