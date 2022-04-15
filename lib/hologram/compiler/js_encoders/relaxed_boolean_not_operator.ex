alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.RelaxedBooleanNotOperator

defimpl JSEncoder, for: RelaxedBooleanNotOperator do
  def encode(%{value: value}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(value, context, opts)
    "Hologram.Interpreter.$relaxed_boolean_not_operator(#{value})"
  end
end
