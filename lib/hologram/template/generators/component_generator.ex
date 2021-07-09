defmodule Hologram.Template.ComponentGenerator do
  alias Hologram.Compiler.Helpers
  alias Hologram.Template.{Builder, Generator}

  def generate(module_name_segs) do
    # DEFER: allow to use module() type as param to module_name/1
    module = Helpers.module(module_name_segs)
    module_name = Helpers.module_name(module_name_segs)

    children_js =
      Builder.build(module)
      |> Generator.generate()

    "{ type: 'component', module: '#{module_name}', children: #{children_js} }"
  end
end
