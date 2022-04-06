alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.RelaxedBooleanNotOperator

defimpl JSEncoder, for: RelaxedBooleanNotOperator do
  def encode(%{value: value}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(Kernel)
    value = JSEncoder.encode(value, context, opts)

    "#{class_name}.$relaxed_boolean_not(#{value})"
  end
end
