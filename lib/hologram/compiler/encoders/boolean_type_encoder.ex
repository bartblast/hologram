alias Hologram.Compiler.Encoder
alias Hologram.Compiler.IR.BooleanType

defimpl Encoder, for: BooleanType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:boolean, "#{value}")
  end
end
