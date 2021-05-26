defmodule Hologram.Template.ComponentGenerator do
  alias Hologram.Compiler.Helpers
  alias Hologram.Template.Generator

  def generate(module, context) do
    module_name = Helpers.module_name(module)
    "{ type: 'component', module: '#{module_name}' }"
  end
end
