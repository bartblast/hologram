defmodule Hologram.Transpiler.StructTypeGenerator do
  alias Hologram.Transpiler.Generator
  alias Hologram.Transpiler.Helpers
  alias Hologram.Transpiler.MapTypeGenerator

  def generate(module, data, context) do
    module_name = Helpers.module_name(module)
    data = MapTypeGenerator.generate_data(data, context)

    "{ type: 'struct', module: '#{module_name}', data: #{data} }"
  end
end
