alias Hologram.Compiler.IR.IntegerType
alias Hologram.Compiler.MapKeyEncoder

defimpl MapKeyEncoder, for: IntegerType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:integer, value)
  end
end
