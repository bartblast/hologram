defmodule Hologram.Template.EmbeddedExpressionParser do
  use Hologram.Commons.Parser

  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.Parser, as: CompilerParser
  alias Hologram.Template.Document.{Expression, TextNode}

  @doc """
  Splits a string which may contain embedded expressions into a list of expression nodes and text nodes.
  """
  def parse(str) do
    nodes =
      ~r/([^\{]*)(\{[^\}]*\})([^\{]*)/
      |> Regex.scan(str)
      |> Enum.reduce([], fn [_, left, expr, right], acc ->
        acc
        |> maybe_include_text_node(left)
        |> maybe_include_expression(expr)
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

  defp get_ir(code) do
    CompilerParser.parse!(code)
    # DEFER: pass actual %Context{} struct received from compiler
    |> Transformer.transform(%Context{})
  end

  defp maybe_include_expression(acc, code) do
    if String.length(code) > 0 do
      acc ++ [%Expression{ir: get_ir(code)}]
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
