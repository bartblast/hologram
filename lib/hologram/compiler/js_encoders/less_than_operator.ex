alias Hologram.Compiler.Context
alias Hologram.Compiler.IR.LessThanOperator
alias Hologram.Compiler.JSEncoder
alias Hologram.Compiler.Opts

defimpl JSEncoder, for: LessThanOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$less_than_operator(#{left}, #{right})"
  end
end
