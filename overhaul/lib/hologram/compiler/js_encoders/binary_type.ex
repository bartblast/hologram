alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.BinaryType

defimpl JSEncoder, for: BinaryType do
  use Hologram.Commons.Encoder

  def encode(%{parts: parts}, %Context{} = context, %Opts{} = opts) do
    "{ type: 'binary', data: #{encode_as_array(parts, context, opts)} }"
  end
end
