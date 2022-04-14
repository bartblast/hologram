alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.NotEqualToOperator

defimpl JSEncoder, for: NotEqualToOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$not_equal_to_operator(#{left}, #{right})"
  end
end
