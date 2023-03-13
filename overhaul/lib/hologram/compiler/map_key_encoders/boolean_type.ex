alias Hologram.Compiler.IR.BooleanType
alias Hologram.Compiler.MapKeyEncoder

defimpl MapKeyEncoder, for: BooleanType do
  use Hologram.Commons.Encoder

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:boolean, value)
  end
end
