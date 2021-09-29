defmodule Hologram.Compiler.BinaryTypeEncoder do
  use Hologram.Compiler.TypeEncoder
  alias Hologram.Compiler.{Context, Opts}

  def encode(parts, %Context{} = context, %Opts{} = opts) do
    "{ type: 'binary', data: #{encode_as_array(parts, context, opts)} }"
  end
end
