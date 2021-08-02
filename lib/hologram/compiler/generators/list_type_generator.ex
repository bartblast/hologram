defmodule Hologram.Compiler.ListTypeGenerator do
  use Hologram.Compiler.TypeEncoder
  alias Hologram.Compiler.{Context, Opts}

  def generate(data, %Context{} = context, %Opts{} = opts) do
    "{ type: 'list', data: #{encode_as_list(data, context, opts)} }"
  end
end
