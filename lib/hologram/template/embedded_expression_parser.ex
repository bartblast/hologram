defmodule Hologram.Template.EmbeddedExpressionParser do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.Parser, as: CompilerParser
  alias Hologram.Template.VDOM.{Expression, TextNode}

  @doc """
  Splits a string which may contain embedded expressions into a list of expression nodes and text nodes.
  """
  def parse(str, %Context{} = context) do
    nodes =
      ~r/([^\{]*)(\{[^\}]*\})([^\{]*)/
      |> Regex.scan(str)
      |> Enum.reduce([], fn [_, left, expr, right], acc ->
        acc
        |> maybe_include_text_node(left)
        |> maybe_include_expression(expr, context)
        |> maybe_include_text_node(right)
      end)

    cond do
      Enum.count(nodes) > 0 ->
        nodes

      str != "" ->
        [%TextNode{content: str}]

      true ->
        []
    end
  end

  defp get_ir(code, context) do
    CompilerParser.parse!(code)
    |> Transformer.transform(context)
  end

  defp maybe_include_expression(acc, code, context) do
    if String.length(code) > 0 do
      acc ++ [%Expression{ir: get_ir(code, context)}]
    else
      acc
    end
  end

  defp maybe_include_text_node(acc, str) do
    if String.length(str) > 0 do
      acc ++ [%TextNode{content: str}]
    else
      acc
    end
  end
end
