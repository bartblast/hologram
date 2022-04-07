alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.ListConcatenationOperator

defimpl JSEncoder, for: ListConcatenationOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$list_concatenation_operator(#{left}, #{right})"
  end
end
