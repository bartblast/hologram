defmodule Hologram.Compiler.ListTypeGenerator do
  use Hologram.Compiler.TypeEncoder
  alias Hologram.Compiler.Context

  def generate(data, %Context{} = context, opts) do
    "{ type: 'list', data: #{encode_as_list(data, context, opts)} }"
  end
end
