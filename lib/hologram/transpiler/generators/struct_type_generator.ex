defmodule Hologram.Transpiler.StructTypeGenerator do
  alias Hologram.Transpiler.Generator
  alias Hologram.Transpiler.Helpers
  alias Hologram.Transpiler.MapTypeGenerator

  def generate(module, data) do
    module_name = Helpers.module_name(module)
    data = MapTypeGenerator.generate_data(data)

    "{ type: 'struct', module: '#{module_name}', data: #{data} }"
  end
end
