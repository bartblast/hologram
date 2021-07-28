defmodule Hologram.Compiler.BinaryTypeEncoder do
  use Hologram.Compiler.TypeEncoder
  alias Hologram.Compiler.Context

  def encode(parts, %Context{} = context, opts) do
    "{ type: 'binary', data: #{encode_as_list(parts, context, opts)} }"
  end
end
