alias Hologram.Compiler.Encoder
alias Hologram.Compiler.IR.IntegerType

defimpl Encoder, for: IntegerType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:integer, "#{value}")
  end
end
