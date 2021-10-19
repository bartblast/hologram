alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.MapType

defimpl Encoder, for: MapType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'map', data: #{encode_map_data(data, context, opts)} }"
  end
end
