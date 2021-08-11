alias Hologram.Compiler.{Context, Encoder, Opts, PrimitiveTypeGenerator}
alias Hologram.Compiler.IR.StringType

defimpl Encoder, for: StringType  do
  def encode(%{value: value}, %Context{}, %Opts{}) do
    value =
      String.replace(value, "'", "\\'", global: true)
      |> String.replace("\n", "\\n", global: true)

    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end
end
