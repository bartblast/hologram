defmodule Hologram.Template.ComponentTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Reflection
  alias Hologram.Compiler.Resolver
  alias Hologram.Template.Commons
  alias Hologram.Template.VDOM.Component

  def transform(module_name, props, children, %Context{} = context) do
    module =
      Helpers.module_name_segments(module_name)
      |> Resolver.resolve(context)

    module_def = Reflection.module_definition(module)
    props = Commons.transform_attr_value(props, context)

    %Component{module: module, module_def: module_def, props: props, children: children}
  end
end
