alias Hologram.Compiler.Encoder
alias Hologram.Compiler.IR.AtomType

defimpl Encoder, for: AtomType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:atom, "'#{value}'")
  end
end
