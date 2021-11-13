alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.BooleanAndOperator

defimpl JSEncoder, for: BooleanAndOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(Kernel)

    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "#{class_name}.$boolean_and(#{left}, #{right})"
  end
end
