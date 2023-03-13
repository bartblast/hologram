alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.MapType

defimpl JSEncoder, for: MapType do
  use Hologram.Commons.Encoder

  def encode(%{data: data}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'map', data: #{encode_map_data(data, context, opts)} }"
  end
end
