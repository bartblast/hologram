alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.EqualToOperator

defimpl JSEncoder, for: EqualToOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$equal_to(#{left}, #{right})"
  end
end
