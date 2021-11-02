alias Hologram.Compiler.IR.BooleanType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: BooleanType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:boolean, "#{value}")
  end
end
