alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.TupleType

defimpl JSEncoder, for: TupleType do
  use Hologram.Commons.Encoder

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'tuple', data: #{encode_as_array(data, context, opts)} }"
  end
end
