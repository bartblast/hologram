alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.StructType

defimpl JSEncoder, for: StructType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{module: module, data: data}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    data = encode_map_data(data, context, opts)

    "{ type: 'struct', className: '#{class_name}', data: #{data} }"
  end
end
