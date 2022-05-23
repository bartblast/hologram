defmodule Hologram.Template.TagAssembler do
  alias Hologram.Template.Helpers
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.TokenHTMLEncoder

  @initial_context %{
    attrs: [],
    attr_key: nil,
    double_quote_open?: 0,
    num_open_braces: 0,
    prev_tokens: [],
    tag_name: nil,
    token_buffer: []
  }

  # see: https://html.spec.whatwg.org/multipage/syntax.html#void-elements
  @void_html_tags [
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr"
  ]

  # TODO: specify void SVG tags
  # see: https://github.com/segmetric/hologram/issues/21
  # see: https://developer.mozilla.org/en-US/docs/Web/SVG/Element
  @void_svg_tags ["path", "rect"]

  # status is one of:
  # text_tag, text_tag_interpolation,
  # start_tag_bracket, start_tag, end_tag_bracket, end_tag,
  # attr_key, attr_assignment,
  # attr_value_text, attr_value_expression, attr_value_interpolation
  def assemble(tokens, status \\ :text_tag, context \\ @initial_context, tags \\ [])

  def assemble([], :text_tag, context, tags) do
    {tokens, _} = flush_token_buffer(context)
    maybe_add_text_tag(tags, tokens)
  end

  def assemble([{:whitespace, _} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:string, _} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:symbol, :=} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:symbol, :"\""} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:symbol, :"\\"} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:symbol, :/} = token | rest], :text_tag, context, tags) do
    assemble_text_tag(context, token, rest, tags)
  end

  def assemble([{:symbol, :"\\{"} | rest], :text_tag, context, tags) do
    assemble_text_tag(context, {:symbol, :"{"}, rest, tags)
  end

  def assemble([{:symbol, :"{"} = token | rest], :text_tag, context, tags) do
    tags = maybe_add_text_tag(tags, context.token_buffer)
    context = context |> reset_expression() |> buffer_token(token) |> add_prev_token(token)
    assemble(rest, :text_tag_interpolation, context, tags)
  end

  def assemble([{:symbol, :"\\}"} | rest], :text_tag, context, tags) do
    assemble_text_tag(context, {:symbol, :"}"}, rest, tags)
  end

  def assemble([{:symbol, :"\""} = token | rest], :text_tag_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> open_double_quote()
    |> assemble_text_tag_interpolation(token, rest, tags)
  end

  def assemble([{:symbol, :"\""} = token | rest], :text_tag_interpolation, %{double_quote_open?: true} = context, tags) do
    context
    |> close_double_quote()
    |> assemble_text_tag_interpolation(token, rest, tags)
  end

  def assemble([{:symbol, :"{"} = token | rest], :text_tag_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> increment_num_open_braces()
    |> assemble_text_tag_interpolation(token, rest, tags)
  end

  def assemble([{:symbol, :"}"} = token | rest], :text_tag_interpolation, %{double_quote_open?: false, num_open_braces: 0} = context, tags) do
    handle_text_tag_interpolation_end(context, token, rest, tags)
  end

  def assemble([{:symbol, :"}"} = token | rest], :text_tag_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> decrement_num_open_braces()
    |> assemble_text_tag_interpolation(token, rest, tags)
  end

  def assemble([token | rest], :text_tag_interpolation, context, tags) do
    assemble_text_tag_interpolation(context, token, rest, tags)
  end

  defp add_expression(tags, tokens) do
    tags ++ [{:expression, TokenHTMLEncoder.encode(tokens)}]
  end

  defp add_prev_token(context, token) do
    %{context | prev_tokens: context.prev_tokens ++ [token]}
  end

  defp assemble_text_tag(context, token, rest, tags) do
    context = context |> buffer_token(token) |> add_prev_token(token)
    assemble(rest, :text_tag, context, tags)
  end

  defp assemble_text_tag_interpolation(context, token, rest, tags) do
    context = context |> buffer_token(token) |> add_prev_token(token)
    assemble(rest, :text_tag_interpolation, context, tags)
  end

  defp buffer_token(context, token) do
    %{context | token_buffer: context.token_buffer ++ [token]}
  end

  defp close_double_quote(context) do
    %{context | double_quote_open?: false}
  end

  defp decrement_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces - 1}
  end

  # TODO: test
  defp error_reason(token, context, type)

  defp error_reason(nil, %{double_quote_open?: true}, :text_tag_interpolation) do
    "Unexpected end of markup because of unclosed double quote inside text interpolation."
  end

  defp error_reason(_, _, _), do:  "Unknown reason."

  defp flush_token_buffer(context) do
    tokens = context.token_buffer
    context = reset_token_buffer(context)
    {tokens, context}
  end

  defp handle_text_tag_interpolation_end(context, token, rest, tags) do
    context =
      context
      |> buffer_token(token)
      |> add_prev_token(token)

    tags = add_expression(tags, context.token_buffer)
    context = reset_text_tag(context)

    assemble(rest, :text_tag, context, tags)
  end

  defp increment_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces + 1}
  end

  defp maybe_add_text_tag(tags, tokens) do
    if Enum.any?(tokens) do
      tags ++ [{:text_tag, TokenHTMLEncoder.encode(tokens)}]
    else
      tags
    end
  end

  defp open_double_quote(context) do
    %{context | double_quote_open?: true}
  end

  defp reset_attr_value(context) do
    %{context | double_quote_opened?: false, num_open_braces: 0}
    |> reset_token_buffer()
  end

  defp reset_expression(context) do
    %{context | double_quote_open?: false, num_open_braces: 0}
    |> reset_token_buffer()
  end

  defp reset_text_tag(context) do
    reset_token_buffer(context)
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end





































  def assemble([{:symbol, :"</"} = token | rest], :text_tag, context, tags) do
    {tokens, context} = flush_token_buffer(context)
    tags = maybe_add_text_tag(tags, tokens)
    context = add_prev_token(context, token)
    assemble(rest, :end_tag_bracket, context, tags)
  end

  def assemble([{:symbol, :<} = token | [{:string, _} | _] = rest], :text_tag, context, tags) do
    tags = maybe_add_text_tag(tags, context.token_buffer)
    context = context |> reset_token_buffer() |> add_prev_token(token)
    assemble(rest, :start_tag_bracket, context, tags)
  end

  def assemble([{:symbol, :<} = token | rest], :text_tag, context, _tags) do
    raise_error(token, rest, context, :text_tag)
  end

  def assemble([{:symbol, :>} = token | rest], :text_tag, context, _tags) do
    raise_error(token, rest, context, :text_tag)
  end

  # def assemble([{:symbol, :"}"} = token | rest], :text_tag, context, tags) do
  #   assemble_text_tag(context, token, rest, tags)
  # end

  def assemble([{:string, str} = token | rest], :start_tag_bracket, context, tags) do
    context = context |> reset_tag(str) |> add_prev_token(token)
    assemble(rest, :start_tag, context, tags)
  end

  def assemble([{:whitespace, _} = token | rest], :start_tag, context, tags) do
    context = add_prev_token(context, token)
    assemble(rest, :start_tag, context, tags)
  end

  def assemble([{:string, str} = token | rest], :start_tag, context, tags) do
    context = context |> put_attr_key(str) |> add_prev_token(token)
    assemble(rest, :attr_key, context, tags)
  end

  def assemble([{:symbol, :"/>"} = token | rest], :start_tag, context, tags) do
    type = Helpers.tag_type(context.tag_name)

    tags =
      if type == :component || is_self_closing_tag?(context.tag_name) do
        add_self_closing_tag(tags, context)
      else
        add_start_tag(tags, context)
      end

    handle_start_tag_end(context, token, rest, tags)
  end

  def assemble([{:symbol, :>} = token | rest], :start_tag, context, tags) do
    tags =
      if is_self_closing_tag?(context.tag_name) do
        add_self_closing_tag(tags, context)
      else
        add_start_tag(tags, context)
      end

    handle_start_tag_end(context, token, rest, tags)
  end

  def assemble([{:whitespace, _} = token | rest], :attr_key, context, tags) do
    context =
      context
      |> add_attr(:boolean, context.attr_key, nil)
      |> add_prev_token(token)

    assemble(rest, :start_tag, context, tags)
  end

  def assemble([{:symbol, :=} = token | rest], :attr_key, context, tags) do
    context = context |> reset_attr_value() |> add_prev_token(token)
    assemble(rest, :attr_assignment, context, tags)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_assignment, context, tags) do
    context = add_prev_token(context, token)
    assemble(rest, :attr_value_literal, context, tags)
  end

  def assemble([{:symbol, :"{"} = token | rest], :attr_assignment, context, tags) do
    context = add_prev_token(context, token)
    assemble(rest, :attr_value_expression, context, tags)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_value_literal, context, tags) do
    handle_attr_value_end(context, :literal, token, rest, tags)
  end

  def assemble([{:symbol, :"{"} = token | rest], :attr_value_literal, context, tags) do
    assemble_attr_value(context, token, rest, tags, :attr_value_interpolation)
  end

  def assemble([token | rest], :attr_value_literal, context, tags) do
    assemble_attr_value(context, token, rest, tags, :attr_value_literal)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
    context
    |> open_double_quote()
    |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_value_expression, %{double_quote_open?: true} = context, tags) do
    context
    |> close_double_quote()
    |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  end

  def assemble([{:symbol, :"{"} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
    context
    |> increment_num_open_braces()
    |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  end

  def assemble([{:symbol, :"}"} = token | rest], :attr_value_expression, %{double_quote_open?: false, num_open_braces: 0} = context, tags) do
    handle_attr_value_end(context, :expression, token, rest, tags)
  end

  def assemble([{:symbol, :"}"} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
    context
    |> decrement_num_open_braces()
    |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  end

  def assemble([token | rest], :attr_value_expression, context, tags) do
    assemble_attr_value(context, token, rest, tags, :attr_value_expression)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> open_double_quote()
    |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  end

  def assemble([{:symbol, :"\""} = token | rest], :attr_value_interpolation, %{double_quote_open?: true} = context, tags) do
    context
    |> close_double_quote()
    |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  end

  def assemble([{:symbol, :"{"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> increment_num_open_braces()
    |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  end

  def assemble([{:symbol, :"}"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false, num_open_braces: 0} = context, tags) do
    assemble_attr_value(context, token, rest, tags, :attr_value_literal)
  end

  def assemble([{:symbol, :"}"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
    context
    |> decrement_num_open_braces()
    |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  end

  def assemble([token | rest], :attr_value_interpolation, context, tags) do
    assemble_attr_value(context, token, rest, tags, :attr_value_interpolation)
  end

  def assemble([{:string, str} = token | rest], :end_tag_bracket, context, tags) do
    context = context |> reset_tag(str) |> add_prev_token(token)
    assemble(rest, :end_tag, context, tags)
  end

  def assemble([{:whitespace, _} = token | rest], :end_tag, context, tags) do
    context = add_prev_token(context, token)
    assemble(rest, :end_tag, context, tags)
  end

  def assemble([{:symbol, :>} = token | rest], :end_tag, context, tags) do
    tags = add_end_tag(tags, context)
    context = add_prev_token(context, token)
    assemble(rest, :text_tag, context, tags)
  end

  def assemble([token | rest], type, context, _) do
    raise_error(token, rest, context, type)
  end

  def assemble([], type, context, _) do
    raise_error(nil, [], context, type)
  end

  defp add_attr(context, type, key, value) do
    %{context | attrs: context.attrs ++ [{type, key, value}]}
  end

  defp add_end_tag(tags, context) do
    tags ++ [{:end_tag, context.tag_name}]
  end

  defp add_start_tag(tags, context) do
    tags ++ [{:start_tag, {context.tag_name, context.attrs}}]
  end

  defp add_self_closing_tag(tags, context) do
    tags ++ [{:self_closing_tag, {context.tag_name, context.attrs}}]
  end

  defp assemble_attr_value(context, token, rest, tags, status) do
    context = context |> buffer_token(token) |> add_prev_token(token)
    assemble(rest, status, context, tags)
  end

  defp escape_non_printable_chars(str) do
    str
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp handle_attr_value_end(context, type, token, rest, tags) do
    context =
      context
      |> buffer_token(token)
      |> add_prev_token(token)
      |> add_attr(type, context.attr_key, context.token_buffer)

    assemble(rest, :start_tag, context, tags)
  end

  defp handle_start_tag_end(context, token, rest, tags) do
    context = context |> reset_token_buffer() |> add_prev_token(token)
    assemble(rest, :text_tag, context, tags)
  end

  defp is_self_closing_tag?(tag_name) do
    is_void_html_tag?(tag_name) || is_void_svg_tag?(tag_name) || tag_name == "slot"
  end

  defp is_void_html_tag?(tag_name) do
    tag_name in @void_html_tags
  end

  defp is_void_svg_tag?(tag_name) do
    tag_name in @void_svg_tags
  end

  defp put_attr_key(context, key) do
    %{context | attr_key: key}
  end

  defp raise_error(token, rest, %{prev_tokens: prev_tokens} = context, type) do
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

    reason = error_reason(token, context, type)

    message = """

    #{reason}
    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^
    """

    raise SyntaxError, message: message
  end

  defp reset_tag(context, tag_name) do
    %{context | attrs: [], tag_name: tag_name}
  end

end
