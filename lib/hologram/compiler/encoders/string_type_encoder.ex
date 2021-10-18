alias Hologram.Compiler.Encoder
alias Hologram.Compiler.IR.StringType

defimpl Encoder, for: StringType do
  import Hologram.Compiler.Encoder.Commons
  
  def encode(%{value: value}, _, _) do
    value =
      String.replace(value, "'", "\\'")
      |> String.replace("\n", "\\n")

    encode_primitive_type(:string, "'#{value}'")
  end
end
