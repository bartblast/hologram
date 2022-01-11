defmodule Hologram.Template.EmbeddedExpressionParser do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.Parser, as: CompilerParser
  alias Hologram.Template.{TokenHTMLEncoder, Tokenizer}
  alias Hologram.Template.VDOM.{Expression, TextNode}

  @doc """
  Splits a string which may contain embedded expressions into a list of expression nodes and text nodes.
  """
  def parse(str, %Context{} = context) do
    acc = %{
      nodes: [],
      num_open_braces: 0,
      prev_tokens: [],
      token_buffer: []
    }

    Tokenizer.tokenize(str)
    |> assemble_nodes(:text, acc, context)
    |> Map.get(:nodes)
  end

  # status is one of: :text, :expression
  defp assemble_nodes(tokens, status, acc, context)

  defp assemble_nodes([], :text, acc, _) do
    maybe_add_text_node(acc)
  end

  # DEFER: implement this case (raise an error)
  # defp assemble_nodes([], :expression, acc, _)

  defp assemble_nodes([{:symbol, :"{"} = token | rest], :text, acc, context) do
    acc =
      acc
      |> maybe_add_text_node()
      |> increment_num_open_braces()
      |> add_prev_token(token)

    assemble_nodes(rest, :expression, acc, context)
  end

  defp assemble_nodes([{:symbol, :"{"} = token | rest], :expression, acc, context) do
    acc
    |> increment_num_open_braces()
    |> assemble_node_part(token, rest, :expression, context)
  end

  defp assemble_nodes(
         [{:symbol, :"}"} = token | rest],
         :expression,
         %{num_open_braces: 1} = acc,
         context
       ) do
    acc =
      acc
      |> maybe_add_expression_part(context)
      |> decrement_num_open_braces()
      |> add_prev_token(token)

    assemble_nodes(rest, :text, acc, context)
  end

  defp assemble_nodes([{:symbol, :"}"} = token | rest], :expression, acc, context) do
    acc
    |> decrement_num_open_braces()
    |> assemble_node_part(token, rest, :expression, context)
  end

  defp assemble_nodes([token | rest], :text, acc, context) do
    assemble_node_part(acc, token, rest, :text, context)
  end

  defp assemble_nodes([token | rest], :expression, acc, context) do
    assemble_node_part(acc, token, rest, :expression, context)
  end

  defp add_prev_token(acc, token) do
    %{acc | prev_tokens: acc.prev_tokens ++ [token]}
  end

  defp assemble_node_part(acc, token, rest, type, context) do
    acc = acc |> buffer_token(token) |> add_prev_token(token)
    assemble_nodes(rest, type, acc, context)
  end

  defp buffer_token(acc, token) do
    %{acc | token_buffer: acc.token_buffer ++ [token]}
  end

  defp decrement_num_open_braces(acc) do
    %{acc | num_open_braces: acc.num_open_braces - 1}
  end

  defp flush_token_buffer(acc) do
    tokens = acc.token_buffer
    acc = %{acc | token_buffer: []}
    {tokens, acc}
  end

  defp get_ir(code, context) do
    CompilerParser.parse!("{#{code}}")
    |> Transformer.transform(context)
  end

  defp increment_num_open_braces(acc) do
    %{acc | num_open_braces: acc.num_open_braces + 1}
  end

  defp maybe_add_expression_part(acc, context) do
    {tokens, acc} = flush_token_buffer(acc)

    if Enum.any?(tokens) do
      code = TokenHTMLEncoder.encode(tokens)
      node = %Expression{ir: get_ir(code, context)}
      %{acc | nodes: acc.nodes ++ [node]}
    else
      acc
    end
  end

  defp maybe_add_text_node(acc) do
    {tokens, acc} = flush_token_buffer(acc)

    if Enum.any?(tokens) do
      node = %TextNode{content: TokenHTMLEncoder.encode(tokens)}
      %{acc | nodes: acc.nodes ++ [node]}
    else
      acc
    end
  end
end
