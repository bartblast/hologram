alias Hologram.Compiler.MapKeyEncoder
alias Hologram.Compiler.IR.IntegerType

defimpl MapKeyEncoder, for: IntegerType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:integer, value)
  end
end
