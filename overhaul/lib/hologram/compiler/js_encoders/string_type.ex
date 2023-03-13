alias Hologram.Compiler.IR.StringType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: StringType do
  use Hologram.Commons.Encoder

  def encode(%{value: value}, _, _) do
    value =
      String.replace(value, "'", "\\'")
      |> String.replace("\n", "\\n")

    encode_primitive_type(:string, "'#{value}'")
  end
end
