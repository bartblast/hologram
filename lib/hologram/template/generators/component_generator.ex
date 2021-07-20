defmodule Hologram.Template.ComponentGenerator do
  alias Hologram.Compiler.Helpers
  alias Hologram.Template.{Builder, Generator}

  def generate(module) do
    module_name = Helpers.module_name(module)

    children_js =
      Builder.build(module)
      |> Generator.generate()

    "{ type: 'component', module: '#{module_name}', children: #{children_js} }"
  end
end
