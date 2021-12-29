# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.TokenCombiner do
  alias Hologram.Template.{Helpers, SyntaxError, TokenHTMLEncoder}

  # see: https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_elems [
    "area", "base", "br", "col", "embed", "hr", "img",
    "input", "link", "meta", "param", "source", "track", "wbr"
  ]

  # status is one of:
  # :text_tag, :start_tag_bracket, :start_tag, :attr_key, :attr_assignment,
  # :attr_value_literal, :attr_value_expression, :end_tag_bracket, :end_tag
  def combine(tokens, status, context, tags)

  def combine([], :text_tag, context, tags) do
    {tokens, _} = flush_token_buffer(context)
    maybe_add_text_tag(tags, tokens)
  end

  def combine([], _, context, _) do
    raise_error(nil, [], context)
  end

  def combine([{:whitespace, _} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:whitespace, _} = token | rest], :start_tag, context, tags) do
    context = add_prev_token(context, token)
    combine(rest, :start_tag, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :attr_key, context, tags) do
    context =
      context
      |> add_attr(:boolean, context.attr_key, nil)
      |> add_prev_token(token)

    combine(rest, :start_tag, context, tags)
  end

  def combine([{:whitespace, _} = token | rest], :end_tag, context, tags) do
    context = add_prev_token(context, token)
    combine(rest, :end_tag, context, tags)
  end

  def combine([{:string, _} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:string, str} = token | rest], :start_tag_bracket, context, tags) do
    context = context |> reset_tag(str) |> add_prev_token(token)
    combine(rest, :start_tag, context, tags)
  end

  def combine([{:string, str} = token | rest], :start_tag, context, tags) do
    context = context |> put_attr_key(str) |> add_prev_token(token)
    combine(rest, :attr_key, context, tags)
  end

  def combine([{:string, str} = token | rest], :end_tag_bracket, context, tags) do
    context = context |> reset_tag(str) |> add_prev_token(token)
    combine(rest, :end_tag, context, tags)
  end

  def combine([{:symbol, :"</"} = token | rest], :text_tag, context, tags) do
    {tokens, context} = flush_token_buffer(context)
    tags = maybe_add_text_tag(tags, tokens)
    context = add_prev_token(context, token)
    combine(rest, :end_tag_bracket, context, tags)
  end

  def combine([{:symbol, :"/>"} = token | rest], :start_tag, context, tags) do
    type = Helpers.tag_type(context.tag_name)

    tags =
      if type == :component || is_void_elem?(context.tag_name) do
        add_void_tag(tags, context)
      else
        add_start_tag(tags, context)
      end

    handle_start_tag_end(context, token, rest, tags)
  end

  def combine([{:symbol, :<} = token | [{:string, _} | _] = rest], :text_tag, context, tags) do
    tags = maybe_add_text_tag(tags, context.token_buffer)
    context = context |> reset_token_buffer() |> add_prev_token(token)
    combine(rest, :start_tag_bracket, context, tags)
  end

  def combine([{:symbol, :<} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :>} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :">"} = token | rest], :start_tag, context, tags) do
    tags =
      if is_void_elem?(context.tag_name) do
        add_void_tag(tags, context)
      else
        add_start_tag(tags, context)
      end

    handle_start_tag_end(context, token, rest, tags)
  end

  def combine([{:symbol, :>} = token| rest], :end_tag, context, tags) do
    tags = add_end_tag(tags, context)
    context = add_prev_token(context, token)
    combine(rest, :text_tag, context, tags)
  end

  def combine([{:symbol, :/} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :=} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :=} = token | rest], :attr_key, context, tags) do
    context = context |> reset_attr_value() |> add_prev_token(token)
    combine(rest, :attr_assignment, context, tags)
  end

  def combine([{:symbol, :"\""} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :"\""} = token | rest], :attr_assignment, context, tags) do
    context = add_prev_token(context, token)
    combine(rest, :attr_value_literal, context, tags)
  end

  def combine([{:symbol, :"\""} = token | rest], :attr_value_literal, context, tags) do
    handle_attr_value_end(context, :literal, token, rest, tags)
  end

  def combine([{:symbol, :"\""} = token| rest], :attr_value_expression, context, tags) do
    combine_attr_value(context, token, rest, tags, :attr_value_expression)
  end

  def combine([{:symbol, :"{"} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :"{"} = token | rest], :attr_assignment, context, tags) do
    context = add_prev_token(context, token)
    combine(rest, :attr_value_expression, context, tags)
  end

  def combine([{:symbol, :"{"} = token | rest], :attr_value_expression, context, tags) do
    context
    |> increment_num_open_braces()
    |> combine_attr_value(token, rest, tags, :attr_value_expression)
  end

  def combine([{:symbol, :"}"} = token | rest], :text_tag, context, tags) do
    combine_text_tag(context, token, rest, tags)
  end

  def combine([{:symbol, :"}"} = token | rest], :attr_value_expression, %{num_open_braces: 0} = context, tags) do
    handle_attr_value_end(context, :expression, token, rest, tags)
  end

  def combine([{:symbol, :"}"} = token | rest], :attr_value_expression, context, tags) do
    context
    |> decrement_num_open_braces()
    |> combine_attr_value(token, rest, tags, :attr_value_expression)
  end

  def combine([token | rest], :attr_value_literal, context, tags) do
    combine_attr_value(context, token, rest, tags, :attr_value_literal)
  end

  def combine([token | rest], :attr_value_expression, context, tags) do
    combine_attr_value(context, token, rest, tags, :attr_value_expression)
  end

  def combine([token | rest], _, context, _) do
    raise_error(token, rest, context)
  end

  defp add_attr(context, type, key, value) do
    %{context | attrs: context.attrs ++ [{type, key, value}]}
  end

  defp add_end_tag(tags, context) do
    tags ++ [{:end_tag, context.tag_name}]
  end

  defp add_prev_token(context, token) do
    %{context | prev_tokens: context.prev_tokens ++ [token]}
  end

  defp add_start_tag(tags, context) do
    tags ++ [{:start_tag, {context.tag_name, context.attrs}}]
  end

  defp add_void_tag(tags, context) do
    tags ++ [{:void_tag, {context.tag_name, context.attrs}}]
  end

  defp buffer_token(context, token) do
    %{context | token_buffer: context.token_buffer ++ [token]}
  end

  defp combine_attr_value(context, token, rest, tags, status) do
    context = context |> buffer_token(token) |> add_prev_token(token)
    combine(rest, status, context, tags)
  end

  defp combine_text_tag(context, token, rest, tags) do
    context = context |> buffer_token(token) |> add_prev_token(token)
    combine(rest, :text_tag, context, tags)
  end

  defp decrement_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces - 1}
  end

  defp escape_non_printable_chars(str) do
    str
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp flush_token_buffer(context) do
    tokens = context.token_buffer
    context = reset_token_buffer(context)
    {tokens, context}
  end

  defp handle_attr_value_end(context, type, token, rest, tags) do
    attr_value = TokenHTMLEncoder.encode(context.token_buffer)

    context =
      context
      |> add_attr(type, context.attr_key, attr_value)
      |> add_prev_token(token)

    combine(rest, :start_tag, context, tags)
  end

  defp handle_start_tag_end(context, token, rest, tags) do
    context = context |> reset_token_buffer() |> add_prev_token(token)
    combine(rest, :text_tag, context, tags)
  end

  defp increment_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces + 1}
  end

  defp is_void_elem?(tag_name) do
    tag_name in @void_elems
  end

  defp maybe_add_text_tag(tags, tokens) do
    if Enum.any?(tokens) do
      tags ++ [{:text_tag, TokenHTMLEncoder.encode(tokens)}]
    else
      tags
    end
  end

  defp put_attr_key(context, key) do
    %{context | attr_key: key}
  end

  defp raise_error(token, rest, %{prev_tokens: prev_tokens}) do
    prev_tokens_str = TokenHTMLEncoder.encode(prev_tokens)
    prev_tokens_len = String.length(prev_tokens_str)

    prev_fragment =
      if prev_tokens_len > 20 do
        String.slice(prev_tokens_str, -20..-1)
      else
        prev_tokens_str
      end
      |> escape_non_printable_chars()

    prev_fragment_len = String.length(prev_fragment)
    indent = String.duplicate(" ", prev_fragment_len)

    current_fragment =
      TokenHTMLEncoder.encode(token)
      |> escape_non_printable_chars()

    next_fragment =
      TokenHTMLEncoder.encode(rest)
      |> String.slice(0, 20)
      |> escape_non_printable_chars()

    message = """

    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^\
    """

    raise SyntaxError, message: message
  end

  defp reset_attr_value(context) do
    %{context | double_quote_opened?: false, num_open_braces: 0, token_buffer: []}
  end

  defp reset_tag(context, tag_name) do
    %{context | attrs: [], tag_name: tag_name}
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end
end
