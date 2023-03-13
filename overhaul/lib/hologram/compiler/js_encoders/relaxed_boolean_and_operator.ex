alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.RelaxedBooleanAndOperator

defimpl JSEncoder, for: RelaxedBooleanAndOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$relaxed_boolean_and_operator(#{left}, #{right})"
  end
end
