alias Hologram.Compiler.IR.BooleanType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: BooleanType do
  use Hologram.Commons.Encoder

  def encode(%{value: value}, _, _) do
    encode_primitive_type(:boolean, "#{value}")
  end
end
