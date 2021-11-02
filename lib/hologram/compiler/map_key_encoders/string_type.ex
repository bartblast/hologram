alias Hologram.Compiler.IR.StringType
alias Hologram.Compiler.MapKeyEncoder

defimpl MapKeyEncoder, for: StringType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:string, value)
  end
end
