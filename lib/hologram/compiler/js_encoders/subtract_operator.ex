alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.SubtractionOperator

defimpl JSEncoder, for: SubtractionOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$subtract(#{left}, #{right})"
  end
end
