defmodule Hologram.Template.ElementNodeTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Template.Commons
  alias Hologram.Template.VDOM.ElementNode

  def transform(tag, children, attrs, %Context{} = context) do
    attrs = transform_attrs(attrs, context)
    %ElementNode{tag: tag, children: children, attrs: attrs}
  end

  defp transform_attrs(attrs, context) do
    Enum.map(attrs, fn {key, value} ->
      [name | modifiers] = String.split(key, ".")

      name = String.to_atom(name)
      value = Commons.transform_attr_value(value, context)
      modifiers = Enum.map(modifiers, &String.to_atom/1)

      {name, %{value: value, modifiers: modifiers}}
    end)
    |> Enum.into(%{})
  end
end
