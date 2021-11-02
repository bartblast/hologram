alias Hologram.Compiler.IR.IntegerType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: IntegerType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:integer, "#{value}")
  end
end
