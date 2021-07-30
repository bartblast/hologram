defmodule Hologram.Template.ElementNodeGenerator do
  alias Hologram.Template.Document.Expression
  alias Hologram.Template.Generator

  def generate(tag, attrs, children) do
    attrs_js = generate_attrs(attrs)
    children_js = generate_children(children)

    "{ type: 'element', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end

  defp generate_attrs(attrs) do
    if Enum.any?(attrs) do
      js =
        attrs
        |> Enum.map(fn {key, value} -> generate_attr(key, value) end)
        |> Enum.join(", ")

      "{ #{js} }"
    else
      "{}"
    end
  end

  defp generate_attr(key, value) do
    [name | modifiers] = String.split(key, ".")
    value = generate_attr_value(value)
    modifiers = encode_modifiers(modifiers)
    "'#{name}': { value: #{value}, modifiers: #{modifiers} }"
  end

  defp generate_attr_value(%Expression{} = expr) do
    Generator.generate(expr)
  end

  defp generate_attr_value(value), do: "'#{value}'"

  defp generate_children(children) do
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
