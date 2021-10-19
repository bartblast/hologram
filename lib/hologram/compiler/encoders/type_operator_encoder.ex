alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.TypeOperator

defimpl Encoder, for: TypeOperator do
  def encode(%{left: left, right: :binary}, %Context{} = context, %Opts{} = opts) do
    value = Encoder.encode(left, context, opts)
    "Elixir_Kernel_SpecialForms.$type(#{value}, 'binary')"
  end
end
