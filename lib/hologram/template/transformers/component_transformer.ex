defmodule Hologram.Template.ComponentTransformer do
  alias Hologram.Compiler.{Context, Helpers, Reflection, Resolver}
  alias Hologram.Template.VDOM.Component
  alias Hologram.Template.EmbeddedExpressionParser

  def transform(module_name, props, children, %Context{} = context) do
    module =
      Helpers.module_name_segments(module_name)
      |> Resolver.resolve(context)

    module_def = Reflection.module_definition(module)
    props = transform_props(props, context)

    %Component{module: module, module_def: module_def, props: props, children: children}
  end

  defp transform_props(props, context) do
    Enum.map(props, fn {type, key, value} ->
      value =
        if(type == :expression, do: "{#{value}}", else: value)
        |> EmbeddedExpressionParser.parse(context)

      {String.to_atom(key), value}
    end)
    |> Enum.into(%{})
  end
end
