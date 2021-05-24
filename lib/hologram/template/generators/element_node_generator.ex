defmodule Hologram.Template.ElementNodeGenerator do
  alias Hologram.Template.{ElementNodeRenderer, Generator}

  def generate(tag, attrs, children, context) do
    attrs_js =
      if Enum.any?(attrs) do
        js =
          Enum.map(attrs, fn {key, value} ->
            "'#{ElementNodeRenderer.render_attr_name(key)}': '#{value}'"
          end)
          |> Enum.join(", ")

        "{ #{js} }"
      else
        "{}"
      end

      children_str =
        Enum.map(children, &Generator.generate(&1, context))
        |> Enum.join(", ")

      children_js = "[#{children_str}]"

    "{ type: 'element', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end
end
