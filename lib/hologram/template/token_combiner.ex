defmodule Hologram.Template.TokenCombiner do
  alias Hologram.Template.SyntaxError

  # status possible values:
  # :text, :start_tag_bracket, :start_tag, :attr_key, :attr_assignment,
  # :attr_value_double_quoted, :attr_value_in_braces, :end_tag_bracket, :end_tag
  def combine(tokens, status, context, acc)














  # TEMPLATE END

  def combine([], :text, context, acc) do
    flush_tokens_to_text_node(context, acc) |> elem(1)
  end

  def combine([], status, context, _acc) do
    raise_error("Unfinished tag", context, [], status, nil)
  end

  # WHITESPACE

  def combine([{:whitespace, char} | rest], :text, context, acc) do
    context = append_token(context, {:whitespace, char})
    combine(rest, :text, context, acc)
  end

  def combine([{:whitespace, char} | rest], :start_tag_bracket, context, _acc) do
    "Whitespace is not allowed between \"<\" and tag name"
    |> raise_error(context, rest, :start_tag_bracket, {:whitespace, char})
  end

  def combine([{:whitespace, _} | rest], :start_tag, context, acc) do
    combine(rest, :start_tag, context, acc)
  end

  def combine([{:whitespace, _} | rest], :attr_key, context, acc) do
    context = append_attr(context, context.attr_key, nil)
    combine(rest, :start_tag, context, acc)
  end

  def combine([{:whitespace, char} | rest], :attr_assignment, context, _acc) do
    message = "Attribute value is missing: tag = #{context.tag}, attribute key = #{context.attr_key}"
    raise SyntaxError, message: message, context: context, rest: rest, status: :attr_assignment, token: {:whitespace, char}
  end

  def combine([{:whitespace, char} | rest], :attr_value_double_quoted, context, acc) do
    context = append_token(context, {:whitespace, char})
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:whitespace, char} | rest], :attr_value_in_braces, context, acc) do
    context = append_token(context, {:whitespace, char})
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:string, str} | rest], :text, context, acc) do
    context = append_token(context, {:string, str})
    combine(rest, :text, context, acc)
  end

  def combine([{:string, str} | rest], :start_tag_bracket, context, acc) do
    context = %{context | tag: str, attrs: []}
    combine(rest, :start_tag, context, acc)
  end

  def combine([{:string, str} | rest], :start_tag, context, acc) do
    context = %{context | attr_key: str}
    combine(rest, :attr_key, context, acc)
  end

  def combine([{:string, str} | rest], :end_tag_bracket, context, acc) do
    context = %{context | tag: str}
    combine(rest, :end_tag, context, acc)
  end

  def combine([{:string, str} | rest], :attr_value_double_quoted, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:string, str}]}
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:string, str} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:string, str}]}
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :<} | rest], :text, context, acc) do
    acc =
      if Enum.any?(context.tokens) do
        acc ++ [{:text, tokens_to_string(context.tokens)}]
      else
        acc
      end

    context = %{context | tokens: []}

    combine(rest, :start_tag_bracket, context, acc)
  end

  def combine([{:symbol, :<} | rest], status, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :<}]}
    combine(rest, status, context, acc)
  end

  def combine([{:symbol, :>} | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]
    context = %{context | tokens: []}
    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :"/>"} | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]
    context = %{context | tokens: []}
    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :"</"} | rest], :text, context, acc) do
    combine(rest, :end_tag_bracket, context, acc)
  end

  def combine([{:symbol, :>} | rest], :end_tag, context, acc) do
    acc = acc ++ [{:end_tag, context.tag}]
    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :=} | rest], :attr_key, context, acc) do
    context = %{context |
      double_quote_opened?: false,
      num_open_braces: 0
    }

    combine(rest, :attr_key, context, acc)
  end

  def combine([{:symbol, :"\""} | rest], :attr_key, context, acc) do
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:symbol, :"{"} | rest], :attr_key, context, acc) do
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :"\""} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :"\""}]}
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :/} | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [{:symbol, :/}]}
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :"\""} | rest], :attr_value_double_quoted, context, acc) do
    attr_value = tokens_to_string(context.tokens)
    attr = {context.attr_key, attr_value}
    context = %{context | attrs: context.attrs ++ [attr]}
    combine(rest, :start_tag, context, acc)
  end

  def combine([{:symbol, :"}"} | rest], :attr_value_in_braces, context, acc) do
    attr_value = "{" <> tokens_to_string(context.tokens) <> "}"
    attr = {context.attr_key, attr_value}
    context = %{context | attrs: context.attrs ++ [attr]}
    combine(rest, :start_tag, context, acc)
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

  defp token_to_string({:string, str}), do: str
  defp token_to_string({:symbol, :"\""}), do: "~Hologram.Template.TokenCombiner[:double_quote]"
  defp token_to_string({:symbol, symbol}), do: to_string(symbol)
  defp token_to_string({:whitespace, char}), do: char

  defp tokens_to_string(tokens) do
    Enum.reduce(tokens, "", &(&2 <> token_to_string(&1)))
  end
end
