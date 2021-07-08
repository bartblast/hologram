defmodule Hologram.Compiler.StructTypeGenerator do
  alias Hologram.Compiler.{Context, Helpers, MapTypeGenerator}

  def generate(module, data, %Context{} = context, opts) do
    module_name = Helpers.module_name(module)
    data = MapTypeGenerator.generate_data(data, context, opts)

    "{ type: 'struct', module: '#{module_name}', data: #{data} }"
  end
end
