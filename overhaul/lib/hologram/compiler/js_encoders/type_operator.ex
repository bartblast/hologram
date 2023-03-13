alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.TypeOperator

defimpl JSEncoder, for: TypeOperator do
  def encode(%{left: left, right: :binary}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(left, context, opts)
    "Hologram.Interpreter.$type_operator(#{value}, 'binary')"
  end
end
