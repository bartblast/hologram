defmodule Hologram.Template.ComponentTransformer do
  alias Hologram.Compiler.{Helpers, Reflection, Resolver}
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.EmbeddedExpressionParser

  def transform(module_name, props, children, aliases) do
    module =
      Helpers.module_segments(module_name)
      |> Resolver.resolve(aliases)

    module_def = Reflection.module_definition(module)
    props = transform_props(props)

    %Component{module: module, module_def: module_def, props: props, children: children}
  end

  defp transform_props(props) do
    Enum.map(props, fn {key, value} ->
      value = EmbeddedExpressionParser.parse(value)
      {String.to_atom(key), value}
    end)
    |> Enum.into(%{})
  end
end
