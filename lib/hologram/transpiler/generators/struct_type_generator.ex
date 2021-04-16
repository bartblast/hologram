defmodule Hologram.Transpiler.Generators.StructTypeGenerator do
  alias Hologram.Transpiler.Generator
  alias Hologram.Transpiler.Generators.MapTypeGenerator
  alias Hologram.Transpiler.Helpers

  def generate(module, data) do
    module_name = Helpers.module_name(module)
    data = MapTypeGenerator.generate_data(data)

    "{ type: 'struct', module: '#{module_name}', data: #{data} }"
  end
end
