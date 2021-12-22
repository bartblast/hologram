defmodule Hologram.Template.Parser do
  use Hologram.Commons.Parser
  alias Hologram.Template.{SyntaxError, Tokenizer}

  @impl Hologram.Commons.Parser
  def parse(markup) do
    context = %{
      attrs: [],
      attr_key: nil,
      double_quote_opened?: 0,
      tag: nil,
      tokens: [],
      num_open_braces: 0
    }

    Tokenizer.tokenize(markup)
    |> merge_tokens(:text, context, [])
    |> Enum.map(&to_html/1)
    |> Enum.join("")
    |> Floki.parse_document!()
    |> remove_empty_text_nodes()
  end

  defp append_attr(context, key, value) do
    %{context | attrs: context.attrs ++ [{key, value}]}
  end

  defp append_token(context, token) do
    %{context | tokens: context.tokens ++ [token]}
  end

  defp flush_tokens_to_text_node(context, acc) do
    acc =
      if Enum.any?(context.tokens) do
        acc ++ [{:text, tokens_to_string(context.tokens)}]
      else
        acc
      end

    context = %{context | tokens: []}

    {context, acc}
  end

  defp raise_error(message, context, rest, status, token) do
    raise SyntaxError, message: message, context: context, rest: rest, status: status, token: token
  end

  defp remove_empty_text_nodes(nodes) when is_list(nodes) do
    nodes
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&remove_empty_text_nodes/1)
  end

  defp remove_empty_text_nodes({tag, attrs, children}) do
    {tag, attrs, remove_empty_text_nodes(children)}
  end

  defp remove_empty_text_nodes(text), do: text

  defp to_html({:start_tag, {tag, attrs}}) do
    attrs = Enum.map(attrs, fn {key, value} -> key <> "=\"" <> value <> "\"" end)
    "<#{tag} #{attrs}>"
  end

  defp to_html({:end_tag, tag}) do
    "</#{tag}>"
  end

  defp to_html({:text, str}) do
    str
  end

  # status possible values:
  # :text, :start_tag_bracket, :start_tag, :attr_key, :attr_assignment,
  # :attr_value_double_quoted, :attr_value_in_braces, :end_tag_bracket, :end_tag
  defp merge_tokens(tokens, status, context, acc)

  # TEMPLATE END

  defp merge_tokens([], :text, context, acc) do
    flush_tokens_to_text_node(context, acc) |> elem(1)
  end

  defp merge_tokens([], status, context, _acc) do
    raise_error("Unfinished tag", context, [], status, nil)
  end

  # WHITESPACE

  defp merge_tokens([{:whitespace, char} | rest], :text, context, acc) do
    context = append_token(context, {:whitespace, char})
    merge_tokens(rest, :text, context, acc)
  end

  defp merge_tokens([{:whitespace, char} | rest], :start_tag_bracket, context, _acc) do
    tag = rest |> hd() |> token_to_string()
    message = "Whitespace is not allowed between \"<\" and tag name: tag = #{tag}"
    raise SyntaxError, message: message, context: context, rest: rest, status: :start_tag_bracket, token: {:whitespace, char}
  end

  defp merge_tokens([{:whitespace, _} | rest], :start_tag, context, acc) do
    merge_tokens(rest, :start_tag, context, acc)
  end

  defp merge_tokens([{:whitespace, _} | rest], :attr_key, context, acc) do
    context = append_attr(context, context.attr_key, nil)
    merge_tokens(rest, :start_tag, context, acc)
  end

  defp merge_tokens([{:whitespace, char} | rest], :attr_assignment, context, _acc) do
    message = "Attribute value is missing: tag = #{context.tag}, attribute key = #{context.attr_key}"
    raise SyntaxError, message: message, context: context, rest: rest, status: :attr_assignment, token: {:whitespace, char}
  end

  defp merge_tokens([{:whitespace, char} | rest], :attr_value_double_quoted, context, acc) do
    context = append_token(context, {:whitespace, char})
    merge_tokens(rest, :attr_value_double_quoted, context, acc)
  end

  defp merge_tokens([{:whitespace, char} | rest], :attr_value_in_braces, context, acc) do
    context = append_token(context, {:whitespace, char})
    merge_tokens(rest, :attr_value_in_braces, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :text, context, acc) do
    context = append_token(context, {:string, str})
    merge_tokens(rest, :text, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :start_tag_bracket, context, acc) do
    context = %{context | tag: str, attrs: []}
    merge_tokens(rest, :start_tag, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :start_tag, context, acc) do
    context = %{context | attr_key: str}
    merge_tokens(rest, :attr_key, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :end_tag_bracket, context, acc) do
    context = %{context | tag: str}
    merge_tokens(rest, :end_tag, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :attr_value_double_quoted, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:string, str}]}
    merge_tokens(rest, :attr_value_double_quoted, context, acc)
  end

  defp merge_tokens([{:string, str} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:string, str}]}
    merge_tokens(rest, :attr_value_in_braces, context, acc)
  end


  defp merge_tokens([{:symbol, :<} | rest], :text, context, acc) do
    acc =
      if Enum.any?(context.tokens) do
        acc ++ [{:text, tokens_to_string(context.tokens)}]
      else
        acc
      end

    context = %{context | tokens: []}

    merge_tokens(rest, :start_tag_bracket, context, acc)
  end

  defp merge_tokens([{:symbol, :<} | rest], status, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :<}]}
    merge_tokens(rest, status, context, acc)
  end

  defp merge_tokens([{:symbol, :>} | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]
    context = %{context | tokens: []}
    merge_tokens(rest, :text, context, acc)
  end

  defp merge_tokens([{:symbol, :"/>"} | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]
    context = %{context | tokens: []}
    merge_tokens(rest, :text, context, acc)
  end

  defp merge_tokens([{:symbol, :"</"} | rest], :text, context, acc) do
    merge_tokens(rest, :end_tag_bracket, context, acc)
  end

  defp merge_tokens([{:symbol, :>} | rest], :end_tag, context, acc) do
    acc = acc ++ [{:end_tag, context.tag}]
    merge_tokens(rest, :text, context, acc)
  end

  defp merge_tokens([{:symbol, :=} | rest], :attr_key, context, acc) do
    context = %{context |
      double_quote_opened?: false,
      num_open_braces: 0
    }

    merge_tokens(rest, :attr_key, context, acc)
  end

  defp merge_tokens([{:symbol, :"\""} | rest], :attr_key, context, acc) do
    merge_tokens(rest, :attr_value_double_quoted, context, acc)
  end

  defp merge_tokens([{:symbol, :"{"} | rest], :attr_key, context, acc) do
    merge_tokens(rest, :attr_value_in_braces, context, acc)
  end

  defp merge_tokens([{:symbol, :"\""} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :"\""}]}
    merge_tokens(rest, :attr_value_in_braces, context, acc)
  end

  defp merge_tokens([{:symbol, :/} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :/}]}
    merge_tokens(rest, :attr_value_in_braces, context, acc)
  end

  defp merge_tokens([{:symbol, :"\""} | rest], :attr_value_double_quoted, context, acc) do
    attr_value = tokens_to_string(context.tokens)
    attr = {context.attr_key, attr_value}
    context = %{context | attrs: context.attrs ++ [attr]}
    merge_tokens(rest, :start_tag, context, acc)
  end

  defp merge_tokens([{:symbol, :"}"} | rest], :attr_value_in_braces, context, acc) do
    attr_value = "{" <> tokens_to_string(context.tokens) <> "}"
    attr = {context.attr_key, attr_value}
    context = %{context | attrs: context.attrs ++ [attr]}
    merge_tokens(rest, :start_tag, context, acc)
  end

  defp token_to_string({:string, str}), do: str
  defp token_to_string({:symbol, :"\""}), do: "~Hologram.Template.Parser[:double_quote]"
  defp token_to_string({:symbol, symbol}), do: to_string(symbol)
  defp token_to_string({:whitespace, char}), do: char

  defp tokens_to_string(tokens) do
    Enum.reduce(tokens, "", &(&2 <> token_to_string(&1)))
  end
end
