alias Hologram.Compiler.{Context, Encoder, Opts, PrimitiveTypeGenerator}
alias Hologram.Compiler.IR.StringType

defimpl Encoder, for: StringType  do
  def encode(%{value: value}, %Context{}, %Opts{}) do
    value = String.replace(value, "'", "\\'")
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end
end
