alias Hologram.Compiler.IR.AtomType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: AtomType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:atom, "'#{value}'")
  end
end
