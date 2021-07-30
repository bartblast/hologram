defmodule Hologram.Template.ElementNodeGenerator do
  alias Hologram.Template.Document.Expression
  alias Hologram.Template.Generator

  def generate(tag, attrs, children) do
    attrs_js = encode_attrs(attrs)
    children_js = encode_children(children)

    "{ type: 'element', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end

  defp encode_attrs(attrs) do
    if Enum.any?(attrs) do
      js =
        attrs
        |> Enum.map(fn {name, spec} -> encode_attr(name, spec) end)
        |> Enum.join(", ")

      "{ #{js} }"
    else
      "{}"
    end
  end

  defp encode_attr(name, %{value: value, modifiers: modifiers}) do
    value = encode_attr_value(value)
    modifiers = encode_modifiers(modifiers)
    "'#{name}': { value: #{value}, modifiers: #{modifiers} }"
  end

  defp encode_attr_value(%Expression{} = expr) do
    Generator.generate(expr)
  end

  defp encode_attr_value(value), do: "'#{value}'"

  defp encode_children(children) do
    js =
      Enum.map(children, &Generator.generate/1)
      |> Enum.join(", ")

    "[#{js}]"
  end

  defp encode_modifiers(modifiers) do
    elems =
      Enum.map(modifiers, &"'#{&1}'")
      |> Enum.join(", ")

    "[#{elems}]"
  end
end
