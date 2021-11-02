alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.TypeOperator

defimpl JSEncoder, for: TypeOperator do
  def encode(%{left: left, right: :binary}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(left, context, opts)
    "Elixir_Kernel_SpecialForms.$type(#{value}, 'binary')"
  end
end
