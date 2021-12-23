# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenCombiner do
  alias Hologram.Template.{SyntaxError, TokenHTMLEncoder}

  # status possible values:
  # :text_tag, :start_tag_bracket, :start_tag, :attr_key, :attr_assignment,
  # :attr_value_double_quoted, :attr_value_in_braces, :end_tag_bracket, :end_tag
  def combine(tokens, status, context, tags)

  # TEMPLATE END

  def combine([], :text_tag, context, tags) do
    {tokens, _} = flush_tokens(context)
    maybe_append_tag(tags, tokens, &{:text_tag, TokenHTMLEncoder.encode(&1)})
  end

  def combine([], _, context, _) do
    raise_error(nil, [], context)
  end

  # WHITESPACE

  def combine([{:whitespace, _} = token | rest], :text_tag, context, tags) do
    context = handle_token(context, token)
    combine(rest, :text_tag, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :start_tag, context, tags) do
    context = accumulate_prev_token(context, token)
    combine(rest, :start_tag, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :attr_key, context, tags) do
    context =
      context
      |> append_attr(context.attr_key, nil)
      |> accumulate_prev_token(token)

    combine(rest, :start_tag, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :attr_value_double_quoted, context, tags) do
    context = handle_token(context, token)
    combine(rest, :attr_value_double_quoted, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :attr_value_in_braces, context, tags) do
    context = handle_token(context, token)
    combine(rest, :attr_value_in_braces, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :end_tag, context, tags) do
    context = accumulate_prev_token(context, token)
    combine(rest, :end_tag, context, tags)
  end

  def combine([{:string, _} = token | rest], :text_tag, context, tags) do
    context = handle_token(context, token)
    combine(rest, :text_tag, context, tags)
  end

  def combine([{:string, str} = token | rest], :start_tag_bracket, context, tags) do
    context = context |> init_tag(str) |> accumulate_prev_token(token)
    combine(rest, :start_tag, context, tags)
  end

  def combine([{:string, str} = token | rest], :start_tag, context, tags) do
    context = %{context | attr_key: str} |> accumulate_prev_token(token)
    combine(rest, :attr_key, context, tags)
  end

  def combine([{:string, _} = token | rest], :attr_value_double_quoted, context, acc) do
    context = handle_token(context, token)
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:string, _} = token | rest], :attr_value_in_braces, context, acc) do
    context = handle_token(context, token)
    combine(rest, :attr_value_in_braces, context, acc)
  end

  def combine([{:string, str} = token | rest], :end_tag_bracket, context, acc) do
    context = context |> init_tag(str) |> accumulate_prev_token(token)
    combine(rest, :end_tag, context, acc)
  end

  def combine([{:symbol, :"</"} = token | rest], :text_tag, context, tags) do
    {tokens, context} = flush_tokens(context)
    build = &{:text_tag, TokenHTMLEncoder.encode(&1)}
    tags = maybe_append_tag(tags, tokens, build)
    context = accumulate_prev_token(context, token)
    combine(rest, :end_tag_bracket, context, tags)
  end

  def combine([{:symbol, :"/>"} = token | rest], :start_tag, context, tags) do
    tags = append_start_tag(tags, context)
    context = context |> reset_tokens() |> accumulate_prev_token(token)
    combine(rest, :text_tag, context, tags)
  end

  def combine([{:symbol, :<} = token | rest], :text_tag, context, tags) do
    build = &{:text_tag, TokenHTMLEncoder.encode(&1)}
    tags = maybe_append_tag(tags, context.tokens, build)
    context = context |> reset_tokens() |> accumulate_prev_token(token)
    combine(rest, :start_tag_bracket, context, tags)
  end

  def combine([{:symbol, :<} = token | rest], status, context, tags) do
    context = context |> append_token(token) |> accumulate_prev_token(token)
    combine(rest, status, context, tags)
  end

  def combine([{:symbol, :>} = token | rest], :start_tag, context, tags) do
    tags = append_start_tag(tags, context)
    context = context |> reset_tokens() |> accumulate_prev_token(token)
    combine(rest, :text_tag, context, tags)
  end

  def combine([{:symbol, :>} = token| rest], :end_tag, context, tags) do
    tags = append_end_tag(tags, context)
    context = accumulate_prev_token(context, token)
    combine(rest, :text_tag, context, tags)
  end

  defp append_attr(context, key, value) do
    %{context | attrs: context.attrs ++ [{key, value}]}
  end

  def append_end_tag(tags, context) do
    tags ++ [{:end_tag, context.tag}]
  end

  def append_start_tag(tags, context) do
    tags ++ [{:start_tag, {context.tag, context.attrs}}]
  end

  defp append_token(context, token) do
    %{context | tokens: context.tokens ++ [token]}
  end

  defp accumulate_prev_token(context, token) do
    %{context | prev_tokens: context.prev_tokens ++ [token]}
  end

  defp flush_tokens(context) do
    tokens = context.tokens
    context = reset_tokens(context)
    {tokens, context}
  end

  defp handle_token(context, token) do
    context
    |> append_token(token)
    |> accumulate_prev_token(token)
  end

  defp init_tag(context, tag) do
    %{context | tag: tag, attrs: []}
  end

  defp maybe_append_tag(tags, tokens, build_tag) do
    if Enum.any?(tokens) do
      tags ++ [build_tag.(tokens)]
    else
      tags
    end
  end

  defp raise_error(token, rest, %{prev_tokens: prev_tokens}) do
    prev_tokens_str = TokenHTMLEncoder.encode(prev_tokens, false)
    prev_tokens_len = String.length(prev_tokens_str)

    prev_fragment =
      if prev_tokens_len > 20 do
        String.slice(prev_tokens_str, -20..-1)
      else
        prev_tokens_str
      end

    prev_fragment_len = String.length(prev_fragment)
    indent = String.duplicate(" ", prev_fragment_len)

    current_fragment = TokenHTMLEncoder.encode(token)

    next_fragment =
      TokenHTMLEncoder.encode(rest)
      |> String.slice(0, 20)

    message = """

    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^\
    """

    raise SyntaxError, message: message
  end

  defp reset_tokens(context) do
    %{context | tokens: []}
  end






































  def combine([{:symbol, :=} = token | rest], :attr_key, context, acc) do
    context = %{context |
      double_quote_opened?: false,
      num_open_braces: 0
    }
    |> accumulate_prev_token(token)

    combine(rest, :attr_assignment, context, acc)
  end

  def combine([{:symbol, :"\""} = token | rest], :attr_assignment, context, acc) do
    context = accumulate_prev_token(context, token)
    combine(rest, :attr_value_double_quoted, context, acc)
  end

  def combine([{:symbol, :"{"} = token | rest], :attr_assignment, context, acc) do
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

  # DEFAULT

  def combine([token | rest], _, context, _) do
    raise_error(token, rest, context)
  end
end
