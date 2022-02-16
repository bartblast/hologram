alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.UnaryNegativeOperator

defimpl JSEncoder, for: UnaryNegativeOperator do
  def encode(%{value: value}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(value, context, opts)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$unary_negative(#{value})"
  end
end
