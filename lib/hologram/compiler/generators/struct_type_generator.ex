defmodule Hologram.Compiler.StructTypeGenerator do
  alias Hologram.Compiler.{Context, Helpers, MapTypeGenerator}

  def generate(module, data, %Context{} = context, opts) do
    class_name = Helpers.class_name(module)
    data = MapTypeGenerator.generate_data(data, context, opts)

    "{ type: 'struct', module: '#{class_name}', data: #{data} }"
  end
end
