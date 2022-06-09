defmodule Hologram.Template.TagAssembler do
  alias Hologram.Template.Helpers
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.TokenHTMLEncoder

  @initial_context %{
    attrs: [],
    attr_key: nil,
    attr_value: [],
    double_quote_open?: 0,
    num_open_braces: 0,
    prev_status: nil,
    processed_tags: [],
    processed_tokens: [],
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
  # text_tag, start_tag_name, start_tag, end_tag_name, end_tag, expression
  # attr_key, attr_assignment, attr_value_literal
  def assemble(context \\ @initial_context, status \\ :text_tag, tokens)

  def assemble(context, :text_tag, []) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> Map.get(:processed_tags)
  end

  def assemble(context, :text_tag, [{:whitespace, _} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:string, _} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :=} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"\""} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"\\"} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :/} = token | rest]) do
    assemble_text_tag(context, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"\\{"} | rest]) do
    assemble_text_tag(context, {:symbol, :"{"}, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"{"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_double_quotes()
    |> reset_braces()
    |> reset_token_buffer()
    |> set_prev_status(:text_tag)
    |> assemble_expression(token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"\\}"} | rest]) do
    assemble_text_tag(context, {:symbol, :"}"}, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :"</"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> set_prev_status(:text_tag)
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:end_tag_name, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :<} = token | [{:string, _} | _] = rest]) do
    context
    |> maybe_add_text_tag()
    |> set_prev_status(:text_tag)
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:start_tag_name, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :<} = token | rest]) do
    raise_error(context, :text_tag, token, rest)
  end

  def assemble(context, :text_tag, [{:symbol, :>} = token | rest]) do
    raise_error(context, :text_tag, token, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, :"\""} = token | rest]) do
    context
    |> open_double_quote()
    |> assemble_expression(token, rest)
  end

  def assemble(%{double_quote_open?: true} = context, :expression, [{:symbol, :"\""} = token | rest]) do
    context
    |> close_double_quote()
    |> assemble_expression(token, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, :"{"} = token | rest]) do
    context
    |> increment_num_open_braces()
    |> assemble_expression(token, rest)
  end

  def assemble(%{double_quote_open?: false, num_open_braces: 0, prev_status: :text_tag} = context, :expression, [{:symbol, :"}"} = token | rest]) do
    context
    |> set_prev_status(:expression)
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_expression_tag()
    |> reset_token_buffer()
    |> assemble(:text_tag, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, :"}"} = token | rest]) do
    context
    |> decrement_num_open_braces()
    |> assemble_expression(token, rest)
  end

  def assemble(context, :expression, [token | rest]) do
    assemble_expression(context, token, rest)
  end

  defp add_expression_tag(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    new_processed_tags = processed_tags ++ [{:expression, TokenHTMLEncoder.encode(token_buffer)}]
    %{context | processed_tags: new_processed_tags}
  end

  defp add_processed_token(%{processed_tokens: processed_tokens} = context, token) do
    %{context | processed_tokens: processed_tokens ++ [token]}
  end

  defp assemble_expression(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> assemble(:expression, rest)
  end

  defp assemble_text_tag(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> assemble(:text_tag, rest)
  end

  defp buffer_token(%{token_buffer: token_buffer} = context, token) do
    %{context | token_buffer: token_buffer ++ [token]}
  end

  defp close_double_quote(context) do
    %{context | double_quote_open?: false}
  end

  defp decrement_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces - 1}
  end

  defp error_reason(context, type, token)

  defp error_reason( _, :text_tag, {:symbol, :<}) do
    """
    Unescaped '<' character inside text node.
    To escape use HTML entity: '&lt;'\
    """
  end

  defp error_reason( _, :text_tag, {:symbol, :>}) do
    """
    Unescaped '>' character inside text node.
    To escape use HTML entity: '&gt;'\
    """
  end

  # # TODO: test
  defp error_reason(%{double_quote_open?: true}, :text_tag_interpolation, nil) do
    "Unexpected end of markup because of unclosed double quote inside text interpolation."
  end

  # # TODO: test
  defp error_reason(context, type, token) do
    """
    Unknown reason.
    token = #{inspect(token)}
    context = #{inspect(context)}
    type = #{inspect(type)}\
    """
  end

  # TODO: test
  defp escape_non_printable_chars(str) do
    str
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp increment_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces + 1}
  end

  defp maybe_add_text_tag(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    if Enum.any?(token_buffer) do
      new_processed_tags = processed_tags ++ [{:text_tag, TokenHTMLEncoder.encode(token_buffer)}]
      %{context | processed_tags: new_processed_tags}
    else
      context
    end
  end

  defp open_double_quote(context) do
    %{context | double_quote_open?: true}
  end

  defp raise_error(%{processed_tokens: processed_tokens} = context, type, token, rest) do
    processed_tokens_str = TokenHTMLEncoder.encode(processed_tokens)
    processed_tokens_len = String.length(processed_tokens_str)

    prev_fragment =
      if processed_tokens_len > 20 do
        String.slice(processed_tokens_str, -20..-1)
      else
        processed_tokens_str
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

    reason = error_reason(context, type, token)

    message = """


    #{reason}

    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^
    """

    raise SyntaxError, message: message
  end

  defp reset_double_quotes(context) do
    %{context | double_quote_open?: false}
  end

  defp reset_braces(context) do
    %{context | num_open_braces: 0}
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end

  defp set_prev_status(context, status) do
    %{context | prev_status: status}
  end


























  # ALREADY REFACTORED

  # # TODO: test
  # def assemble([{:whitespace, _} = token | rest], :start_tag, context, tags) do
  #   context = add_prev_token(context, token)
  #   assemble(rest, :start_tag, context, tags)
  # end

  # # TODO: test
  # def assemble([{:string, str} = token | rest], :start_tag, context, tags) do
  #   context = context |> put_attr_key(str) |> add_prev_token(token)
  #   assemble(rest, :attr_key, context, tags)
  # end

  # def assemble([{:symbol, :"/>"} = token | rest], :start_tag, context, tags) do
  #   type = Helpers.tag_type(context.tag_name)

  #   tags =
  #     if type == :component || is_self_closing_tag?(context.tag_name) do
  #       add_self_closing_tag(tags, context)
  #     else
  #       add_start_tag(tags, context)
  #     end

  #   handle_start_tag_end(context, token, rest, tags)
  # end

  # def assemble([{:symbol, :>} = token | rest], :start_tag, context, tags) do
  #   tags =
  #     if is_self_closing_tag?(context.tag_name) do
  #       add_self_closing_tag(tags, context)
  #     else
  #       add_start_tag(tags, context)
  #     end

  #   handle_start_tag_end(context, token, rest, tags)
  # end

  # def assemble([{:string, str} = token | rest], :start_tag_name, context, tags) do
  #   context = context |> reset_tag(str) |> add_prev_token(token)
  #   assemble(rest, :start_tag, context, tags)
  # end

  # # TODO: test
  # def assemble([{:whitespace, _} = token | rest], :attr_key, context, tags) do
  #   context =
  #     context
  #     |> add_prev_token(token)
  #     |> commit_attribute()

  #   assemble(rest, :start_tag, context, tags)
  # end

  # # TODO: test
  # def assemble([{:symbol, :=} = token | rest], :attr_key, context, tags) do
  #   context = context |> reset_attr_value() |> add_prev_token(token)
  #   assemble(rest, :attr_assignment, context, tags)
  # end

  # # TODO: test
  # def assemble([{:symbol, :"\""} = token | rest], :attr_assignment, context, tags) do
  #   context = add_prev_token(context, token)
  #   assemble(rest, :attr_value_literal, context, tags)
  # end

  # # TODO: test
  # def assemble([{:symbol, :"\""} = token | rest], :attr_value_literal, context, tags) do
  #   handle_attr_value_end(context, :literal, token, rest, tags)
  # end

  # defp add_attr_value_part(context, part) do
  #   %{context | attr_value: context.attr_value ++ [part]}
  # end

  # defp add_prev_token(context, token) do
  #   %{context | prev_tokens: context.prev_tokens ++ [token]}
  # end

  # defp add_self_closing_tag(tags, context) do
  #   tags ++ [{:self_closing_tag, {context.tag_name, context.attrs}}]
  # end

  # defp add_start_tag(tags, context) do
  #   tags ++ [{:start_tag, {context.tag_name, context.attrs}}]
  # end

  # defp commit_attribute(context) do
  #   %{context | attrs: context.attrs ++ [{context.attr_key, context.attr_value}]}
  # end

  # # TODO: test
  # defp handle_attr_value_end(context, part_type, token, rest, tags) do
  #   context =
  #     if part_type == :expression do
  #       buffer_token(context, token)
  #     else
  #       context
  #     end

  #   part = {part_type, TokenHTMLEncoder.encode(context.token_buffer)}

  #   context =
  #     context
  #     |> add_prev_token(token)
  #     |> add_attr_value_part(part)
  #     |> commit_attribute()

  #   assemble(rest, :start_tag, context, tags)
  # end

  # defp handle_start_tag_end(context, token, rest, tags) do
  #   context = context |> reset_token_buffer() |> add_prev_token(token)
  #   assemble(rest, :text_tag, context, tags)
  # end

  # defp is_self_closing_tag?(tag_name) do
  #   is_void_html_tag?(tag_name) || is_void_svg_tag?(tag_name) || tag_name == "slot"
  # end

  # defp is_void_html_tag?(tag_name) do
  #   tag_name in @void_html_tags
  # end

  # defp is_void_svg_tag?(tag_name) do
  #   tag_name in @void_svg_tags
  # end

  # defp reset_attr_value(context) do
  #   %{context | attr_value: [], double_quote_opened?: false, num_open_braces: 0}
  #   |> reset_token_buffer()
  # end

  # defp reset_expression(context) do
  #   %{context | double_quote_open?: false, num_open_braces: 0}
  #   |> reset_token_buffer()
  # end

  # defp reset_tag(context, tag_name) do
  #   %{context | attrs: [], tag_name: tag_name}
  # end














































  # TO REFACTOR

  # def assemble([{:symbol, :"}"} = token | rest], :expression, %{double_quote_open?: false, num_open_braces: 0, prev_status: :attribute_value_litera} = context, tags) do

  # TODO: test
  # def assemble([{:symbol, :"{"} = token | rest], :attr_assignment, context, tags) do
  #   context = add_prev_token(context, token)
  #   assemble(rest, :attr_value_expression, context, tags)
  # end

  # defp assemble_attr_value(context, token, rest, tags, status) do
  #   context = context |> buffer_token(token) |> add_prev_token(token)
  #   assemble(rest, status, context, tags)
  # end

  # def assemble([{:symbol, :"{"} = token | rest], :attr_value_literal, context, tags) do
  #   assemble_attr_value(context, token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([token | rest], :attr_value_literal, context, tags) do
  #   assemble_attr_value(context, token, rest, tags, :attr_value_literal)
  # end

  # def assemble([{:symbol, :"\""} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> open_double_quote()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  # end

  # def assemble([{:symbol, :"\""} = token | rest], :attr_value_expression, %{double_quote_open?: true} = context, tags) do
  #   context
  #   |> close_double_quote()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  # end

  # def assemble([{:symbol, :"{"} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> increment_num_open_braces()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  # end

  # def assemble([{:symbol, :"}"} = token | rest], :attr_value_expression, %{double_quote_open?: false, num_open_braces: 0} = context, tags) do
  #   handle_attr_value_end(context, :expression, token, rest, tags)
  # end

  # def assemble([{:symbol, :"}"} = token | rest], :attr_value_expression, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> decrement_num_open_braces()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_expression)
  # end

  # def assemble([token | rest], :attr_value_expression, context, tags) do
  #   assemble_attr_value(context, token, rest, tags, :attr_value_expression)
  # end

  # def assemble([{:symbol, :"\""} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> open_double_quote()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([{:symbol, :"\""} = token | rest], :attr_value_interpolation, %{double_quote_open?: true} = context, tags) do
  #   context
  #   |> close_double_quote()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([{:symbol, :"{"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> increment_num_open_braces()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([{:symbol, :"}"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false, num_open_braces: 0} = context, tags) do
  #   assemble_attr_value(context, token, rest, tags, :attr_value_text)
  # end

  # def assemble([{:symbol, :"}"} = token | rest], :attr_value_interpolation, %{double_quote_open?: false} = context, tags) do
  #   context
  #   |> decrement_num_open_braces()
  #   |> assemble_attr_value(token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([token | rest], :attr_value_interpolation, context, tags) do
  #   assemble_attr_value(context, token, rest, tags, :attr_value_interpolation)
  # end

  # def assemble([{:string, str} = token | rest], :end_tag_name, context, tags) do
  #   context = context |> reset_tag(str) |> add_prev_token(token)
  #   assemble(rest, :end_tag, context, tags)
  # end

  # def assemble([{:whitespace, _} = token | rest], :end_tag, context, tags) do
  #   context = add_prev_token(context, token)
  #   assemble(rest, :end_tag, context, tags)
  # end

  # def assemble([{:symbol, :>} = token | rest], :end_tag, context, tags) do
  #   tags = add_end_tag(tags, context)
  #   context = add_prev_token(context, token)
  #   assemble(rest, :text_tag, context, tags)
  # end

  # def assemble([token | rest], type, context, _) do
  #   raise_error(context, type, token, rest)
  # end

  # def assemble([], type, context, _) do
  #   raise_error(context, type, nil, [])
  # end

  # defp add_end_tag(tags, context) do
  #   tags ++ [{:end_tag, context.tag_name}]
  # end

  # defp put_attr_key(context, key) do
  #   %{context | attr_key: key}
  # end
end
