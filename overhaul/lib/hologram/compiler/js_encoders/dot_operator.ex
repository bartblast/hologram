alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.DotOperator

defimpl JSEncoder, for: DotOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$dot_operator(#{left}, #{right})"
  end
end
