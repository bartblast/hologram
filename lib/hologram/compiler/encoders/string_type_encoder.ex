alias Hologram.Compiler.{Encoder, PrimitiveTypeGenerator}
alias Hologram.Compiler.IR.StringType

defimpl Encoder, for: StringType  do
  def encode(%{value: value}, _, _) do
    value =
      String.replace(value, "'", "\\'", global: true)
      |> String.replace("\n", "\\n", global: true)

    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end
end
