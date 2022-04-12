alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.ListType

defimpl JSEncoder, for: ListType do
  use Hologram.Commons.Encoder

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'list', data: #{encode_as_array(data, context, opts)} }"
  end
end
