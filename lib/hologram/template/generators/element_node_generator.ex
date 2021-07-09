defmodule Hologram.Template.ElementNodeGenerator do
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
        |> Enum.map(fn {key, value} ->
          "'#{key}': '#{value}'"
        end)
        |> Enum.join(", ")

      "{ #{js} }"
    else
      "{}"
    end
  end

  defp generate_children(children) do
    js =
      Enum.map(children, &Generator.generate/1)
      |> Enum.join(", ")

    "[#{js}]"
  end
end
