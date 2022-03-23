alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.RelaxedBooleanAndOperator

defimpl JSEncoder, for: RelaxedBooleanAndOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(Kernel)

    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "#{class_name}.$relaxed_boolean_and(#{left}, #{right})"
  end
end
