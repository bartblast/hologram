# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenCombiner do
  alias Hologram.Template.{SyntaxError, TokenHTMLEncoder}

  # status possible values:
  # :text, :start_tag_bracket, :start_tag, :attr_key, :attr_assignment,
  # :attr_value_double_quoted, :attr_value_in_braces, :end_tag_bracket, :end_tag
  def combine(tokens, status, context, acc)

  # TEMPLATE END

  def combine([], :text, context, acc) do
    flush_tokens_to_text_node(context, acc) |> elem(1)
  end

  def combine([], _, context, _) do
    raise_error(nil, [], context)
  end

  # WHITESPACE

  def combine([{:whitespace, _} = token | rest], :text, context, acc) do
    context =
      context
      |> append_token(token)
      |> accumulate_prev_token(token)

    combine(rest, :text, context, acc)
  end

  def combine([{:whitespace, char} | rest], :start_tag_bracket, context, _acc) do
    "Whitespace is not allowed between \"<\" and tag name"
    raise_error({:whitespace, char}, rest, context)
    # |> raise_error(context, rest, :start_tag_bracket, {:whitespace, char})
  end

  def combine([{:whitespace, _} = token | rest], :start_tag, context, acc) do
    context = accumulate_prev_token(context, token)
    combine(rest, :start_tag, context, acc)
  end

  def combine([{:whitespace, _} = token | rest], :attr_key, context, acc) do
    context =
      context
      |> append_attr(context.attr_key, nil)
      |> accumulate_prev_token(token)

    combine(rest, :start_tag, context, acc)
  end

  def combine([{:whitespace, char} | rest], :attr_assignment, context, _acc) do
    message = "Attribute value is missing: tag = #{context.tag}, attribute key = #{context.attr_key}"
    raise SyntaxError, message: message, context: context, rest: rest, status: :attr_assignment, token: {:whitespace, char}
  end

  def combine([{:whitespace, _} = token | rest], :attr_value_double_quoted, context, acc) do
    context =
      append_token(context, token)
      |> accumulate_prev_token(token)

    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:whitespace, _} = token | rest], :attr_value_in_braces, context, acc) do
    context =
      append_token(context, token)
      |> accumulate_prev_token(token)

    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:string, _} = token | rest], :text, context, acc) do
    context = append_token(context, token)
    |> accumulate_prev_token(token)

    combine(rest, :text, context, acc)
  end

  def combine([{:string, str} = token | rest], :start_tag_bracket, context, acc) do
    context =
      %{context | tag: str, attrs: []}
      |> accumulate_prev_token(token)

    combine(rest, :start_tag, context, acc)
  end

  def combine([{:string, str} = token | rest], :start_tag, context, acc) do
    context =
      %{context | attr_key: str}
      |> accumulate_prev_token(token)

    combine(rest, :attr_key, context, acc)
  end

  def combine([{:string, str} = token | rest], :end_tag_bracket, context, acc) do
    context = %{context | tag: str}
    |> accumulate_prev_token(token)

    combine(rest, :end_tag, context, acc)
  end

  def combine([{:string, _} = token | rest], :attr_value_double_quoted, context, acc) do
    context =
      %{context | tokens: context.tokens ++ [token]}
      |> accumulate_prev_token(token)

    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:string, _} = token | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [token]}
    |> accumulate_prev_token(token)

    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :<} = token | rest], :text, context, acc) do
    acc =
      if Enum.any?(context.tokens) do
        acc ++ [{:text, TokenHTMLEncoder.encode(context.tokens)}]
      else
        acc
      end

    context = %{context | tokens: []}
    |> accumulate_prev_token(token)

    combine(rest, :start_tag_bracket, context, acc)
  end

  def combine([{:symbol, :<} = token | rest], status, context, acc) do
    context = %{context | tokens: context.tokens ++ [token]}
    |> accumulate_prev_token(token)

    combine(rest, status, context, acc)
  end

  def combine([{:symbol, :>} = token | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]

    context = %{context | tokens: []}
    |> accumulate_prev_token(token)

    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :"/>"} = token | rest], :start_tag, context, acc) do
    acc = acc ++ [{:start_tag, {context.tag, context.attrs}}]

    context = %{context | tokens: []}
    |> accumulate_prev_token(token)

    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :"</"} = token | rest], :text, context, acc) do
    context = accumulate_prev_token(context, token)
    combine(rest, :end_tag_bracket, context, acc)
  end

  def combine([{:symbol, :>} = token| rest], :end_tag, context, acc) do
    acc = acc ++ [{:end_tag, context.tag}]
    context= accumulate_prev_token(context, token)
    combine(rest, :text, context, acc)
  end

  def combine([{:symbol, :=} = token | rest], :attr_key, context, acc) do
    context = %{context |
      double_quote_opened?: false,
      num_open_braces: 0
    }
    |> accumulate_prev_token(token)

    combine(rest, :attr_key, context, acc)
  end

  def combine([{:symbol, :"\""} = token | rest], :attr_key, context, acc) do
    context = accumulate_prev_token(context, token)
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:symbol, :"{"} = token | rest], :attr_key, context, acc) do
    context = accumulate_prev_token(context, token)
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :"\""} = token| rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [token]}
    |> accumulate_prev_token(token)

    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :/} = token | rest], :attr_value_in_braces, context, acc) do
    context = %{context | tokens: context.tokens ++ [token]}
    |> accumulate_prev_token(token)

    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:symbol, :"\""} = token | rest], :attr_value_double_quoted, context, acc) do
    attr_value = TokenHTMLEncoder.encode(context.tokens)
    attr = {context.attr_key, attr_value}

    context = %{context | attrs: context.attrs ++ [attr]}
    |> accumulate_prev_token(token)

    combine(rest, :start_tag, context, acc)
  end

  def combine([{:symbol, :"}"} = token | rest], :attr_value_in_braces, context, acc) do
    attr_value = "{" <> TokenHTMLEncoder.encode(context.tokens) <> "}"
    attr = {context.attr_key, attr_value}

    context = %{context | attrs: context.attrs ++ [attr]}
    |> accumulate_prev_token(token)

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
        acc ++ [{:text, TokenHTMLEncoder.encode(context.tokens)}]
      else
        acc
      end

    context = %{context | tokens: []}

    {context, acc}
  end

  defp raise_error(token, rest, %{prev_tokens: prev_tokens}) do
    prev_tokens_str = TokenHTMLEncoder.encode(prev_tokens)
    prev_tokens_len = String.length(prev_tokens_str)

    prev_fragment =
      if prev_tokens_len > 10 do
        String.slice(prev_tokens_str, -10..-1)
      else
        prev_tokens_str
      end

    prev_fragment_len = String.length(prev_fragment)

    prelude_len = "** (Hologram.Template.SyntaxError) " |> String.length()
    indent_len = prelude_len + prev_fragment_len
    indent = String.duplicate(" ", indent_len)

    current_token_str = TokenHTMLEncoder.encode(token)
    next_tokens_str = TokenHTMLEncoder.encode(rest)

    message = prev_fragment <> current_token_str <> next_tokens_str <> "\n" <> indent <> "^"

    raise SyntaxError, message: message
  end

  defp accumulate_prev_token(context, token) do
    %{context | prev_tokens: context.prev_tokens ++ [token]}
  end
end
