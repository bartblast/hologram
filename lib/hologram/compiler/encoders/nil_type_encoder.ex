alias Hologram.Compiler.Encoder
alias Hologram.Compiler.IR.NilType

defimpl Encoder, for: NilType do
  def encode(_, _, _) do
    "{ type: 'nil' }"
  end
end
