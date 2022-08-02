defmodule Hologram.Template.Commons do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode

  def transform_attr_value(value, context) do
    Enum.map(value, fn {type, str} ->
      case type do
        :expression ->
          %Expression{ir: Reflection.ir(str, context)}

        :literal ->
          %TextNode{content: str}
      end
    end)
  end
end
