alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.EqualToOperator

defimpl JSEncoder, for: EqualToOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$equal_to_operator(#{left}, #{right})"
  end
end
