defmodule Hologram.Template.Generator do
  alias Hologram.Template.VirtualDOM.{Expression, TagNode, TextNode}
  alias Hologram.Template.{ExpressionGenerator, Renderer}
  alias Hologram.Compiler.IR.ModuleAttributeDefinition
  alias Hologram.Compiler.{Normalizer, Transformer}

  def generate(virtual_dom, context \\ [module_attributes: []])

  def generate(%Expression{ir: ir}, context) do
    ExpressionGenerator.generate(ir, context)
  end

  def generate(%TagNode{attrs: attrs, children: children, tag: tag}, context) do
    attrs_js =
      if Enum.any?(attrs) do
        js =
          Enum.map(attrs, fn {key, value} ->
            "'#{Renderer.render_attr_name(key)}': '#{value}'"
          end)
          |> Enum.join(", ")

        "{ #{js} }"
      else
        "{}"
      end

      children_str =
        Enum.map(children, &generate(&1, context))
        |> Enum.join(", ")

      children_js = "[#{children_str}]"

    "{ type: 'tag_node', tag: '#{tag}', attrs: #{attrs_js}, children: #{children_js} }"
  end

  def generate(%TextNode{text: text}, _) do
    text =
      String.replace(text, "\n", "\\n", global: true)
      |> String.replace("'", "\\'", global: true)

    "{ type: 'text_node', text: '#{text}' }"
  end

  def generate(nodes, state) when is_list(nodes) do
    module_attributes =
      Enum.map(state, fn {key, value} ->
        value =
          Macro.escape(value)
          |> Normalizer.normalize()
          |> Transformer.transform()

        %ModuleAttributeDefinition{name: key, value: value}
      end)

    context = [module_attributes: module_attributes]

    nodes_js =
      Enum.map(nodes, &generate(&1, context))
      |> Enum.join(", ")

    "[#{nodes_js}]"
  end
end
