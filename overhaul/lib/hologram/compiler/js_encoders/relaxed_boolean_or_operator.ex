alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.RelaxedBooleanOrOperator

defimpl JSEncoder, for: RelaxedBooleanOrOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$relaxed_boolean_or_operator(#{left}, #{right})"
  end
end
