alias Hologram.Compiler.MapKeyEncoder
alias Hologram.Compiler.IR.AtomType

defimpl MapKeyEncoder, for: AtomType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_key(:atom, value)
  end
end
