alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.DivisionOperator

defimpl JSEncoder, for: DivisionOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$division_operator(#{left}, #{right})"
  end
end
