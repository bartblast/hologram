alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.TupleType

defimpl Encoder, for: TupleType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'tuple', data: #{encode_as_array(data, context, opts)} }"
  end
end
