alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.ListType

defimpl Encoder, for: ListType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'list', data: #{encode_as_array(data, context, opts)} }"
  end
end
