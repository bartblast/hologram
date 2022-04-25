alias Hologram.Compiler.IR.FloatType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: FloatType do
  use Hologram.Commons.Encoder

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:float, "#{value}")
  end
end
