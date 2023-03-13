alias Hologram.Compiler.IR.NilType
alias Hologram.Compiler.JSEncoder

defimpl JSEncoder, for: NilType do
  def encode(_, _, _) do
    "{ type: 'nil' }"
  end
end
