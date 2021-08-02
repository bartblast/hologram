defmodule Hologram.Compiler.StructTypeGenerator do
  alias Hologram.Compiler.{Context, Helpers, MapTypeGenerator, Opts}

  def generate(module, data, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    data = MapTypeGenerator.generate_data(data, context, opts)

    "{ type: 'struct', module: '#{class_name}', data: #{data} }"
  end
end
