defmodule Hologram.Template.ComponentGenerator do
  alias Hologram.Compiler.Helpers
  alias Hologram.Template.Generator

  def generate(module, children) do
    class_name = Helpers.class_name(module)
    children = Generator.generate(children)

    "{ type: 'component', module: '#{class_name}', children: #{children} }"
  end
end
