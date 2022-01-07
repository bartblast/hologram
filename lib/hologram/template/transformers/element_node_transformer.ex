defmodule Hologram.Template.ElementNodeTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.EmbeddedExpressionParser

  def transform(tag, children, attrs, %Context{} = context) do
    attrs = transform_attrs(attrs, context)
    %ElementNode{tag: tag, children: children, attrs: attrs}
  end

  defp transform_attrs(attrs, context) do
    Enum.map(attrs, fn {type, key, value} ->
      [name | modifiers] = String.split(key, ".")

      name = String.to_atom(name)
      modifiers = Enum.map(modifiers, &String.to_atom/1)

      value =
        case type do
          :boolean ->
            nil

          :expression ->
            "{#{value}}" |> EmbeddedExpressionParser.parse(context)

          :literal ->
            EmbeddedExpressionParser.parse(value, context)
        end

      {name, %{value: value, modifiers: modifiers}}
    end)
    |> Enum.into(%{})
  end
end
