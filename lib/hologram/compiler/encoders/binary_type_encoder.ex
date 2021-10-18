alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.BinaryType

defimpl Encoder, for: BinaryType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{parts: parts}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'binary', data: #{encode_as_array(parts, context, opts)} }"
  end
end
