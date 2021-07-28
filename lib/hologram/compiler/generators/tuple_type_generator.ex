defmodule Hologram.Compiler.TupleTypeGenerator do
  use Hologram.Compiler.TypeEncoder
  alias Hologram.Compiler.Context

  def generate(data, %Context{} = context, opts) do
    "{ type: 'tuple', data: #{encode_as_list(data, context, opts)} }"
  end
end
