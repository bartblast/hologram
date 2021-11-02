alias Hologram.Compiler.IR.AtomType
alias Hologram.Compiler.MapKeyEncoder

defimpl MapKeyEncoder, for: AtomType do
  use Hologram.Commons.Encoder

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:atom, value)
  end
end
