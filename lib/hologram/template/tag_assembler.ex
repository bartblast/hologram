defmodule Hologram.Template.TagAssembler do
  alias Hologram.Template.Helpers
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.TokenHTMLEncoder

  @initial_context %{
    attrs: [],
    attr_key: nil,
    attr_value: [],
    double_quote_open?: false,
    node_type: :text_node,
    num_open_braces: 0,
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
  # text, start_tag_name, start_tag, end_tag_name, end_tag, expression
  # attr_key, attr_assignment, attr_value_literal
  def assemble(context \\ @initial_context, status \\ :text, tokens)

  def assemble(context, :text, []) do
    context
    |> maybe_add_text()
    |> reset_token_buffer()
    |> Map.get(:processed_tags)
  end

  def assemble(context, :text, [{:whitespace, _} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:string, _} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, :=} = token | rest]) do
    assemble_text(context, token, rest)
  end

  # TODO: test
  def assemble(%{node_type: :attribute_value_text} = context, :text, [{:symbol, :"\""} = token | rest]) do
    handle_attr_value_end(context, :literal, token, rest)
  end

  def assemble(context, :text, [{:symbol, :"\""} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, :"\\"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, :/} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, :"\\{"} | rest]) do
    assemble_text(context, {:symbol, :"{"}, rest)
  end

  def assemble(context, :text, [{:symbol, :"{"} = token | rest]) do
    context
    |> maybe_add_text()
    |> reset_double_quotes()
    |> reset_braces()
    |> reset_token_buffer()
    |> assemble_expression(token, rest)
  end

  def assemble(context, :text, [{:symbol, :"\\}"} | rest]) do
    assemble_text(context, {:symbol, :"}"}, rest)
  end

  def assemble(context, :text, [{:symbol, :"</"} = token | rest]) do
    context
    |> maybe_add_text()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:end_tag_name, rest)
  end

  def assemble(context, :text, [{:symbol, :<} = token | [{:string, _} | _] = rest]) do
    context
    |> maybe_add_text()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_node_type(:element_node)
    |> assemble(:start_tag_name, rest)
  end

  def assemble(context, :text, [{:symbol, :<} = token | rest]) do
    raise_error(context, :text, token, rest)
  end

  def assemble(context, :text, [{:symbol, :>} = token | rest]) do
    raise_error(context, :text, token, rest)
  end

  def assemble(context, :start_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> reset_attrs()
    |> set_tag_name(tag_name)
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  # # TODO: test
  def assemble(context, :start_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  # TODO: test
  def assemble(context, :start_tag, [{:string, str} = token | rest]) do
    context
    |> set_attr_key(str)
    |> reset_attr_value()
    |> reset_double_quotes()
    |> reset_braces()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:attr_key, rest)
  end

  def assemble(context, :start_tag, [{:symbol, :"/>"} = token | rest]) do
    handle_start_tag_end(context, token, rest)
  end

  def assemble(context, :start_tag, [{:symbol, :>} = token | rest]) do
    handle_start_tag_end(context, token, rest)
  end

  def assemble(context, :end_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> set_tag_name(tag_name)
    |> add_processed_token(token)
    |> assemble(:end_tag, rest)
  end

  def assemble(context, :end_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:end_tag, rest)
  end

  def assemble(context, :end_tag, [{:symbol, :>} = token | rest]) do
    context
    |> add_end_tag()
    |> add_processed_token(token)
    |> set_node_type(:text_node)
    |> assemble(:text, rest)
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

  def assemble(%{double_quote_open?: false, num_open_braces: 0, node_type: :text_node} = context, :expression, [{:symbol, :"}"} = token | rest]) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_expression_tag()
    |> reset_token_buffer()
    |> assemble(:text, rest)
  end

  # TODO: test
  def assemble(%{double_quote_open?: false, num_open_braces: 0, node_type: :attribute_value_expression} = context, :expression, [{:symbol, :"}"} = token | rest]) do
    handle_attr_value_end(context, :expression, token, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, :"}"} = token | rest]) do
    context
    |> decrement_num_open_braces()
    |> assemble_expression(token, rest)
  end

  def assemble(context, :expression, [token | rest]) do
    assemble_expression(context, token, rest)
  end

  def assemble(context, :attr_key, [{:whitespace, _} = token | rest]) do
    context
    |> flush_attribute()
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  def assemble(context, :attr_key, [{:symbol, :>} = token | rest]) do
    context
    |> flush_attribute()
    |> handle_start_tag_end(token, rest)
  end

  # TODO: test
  def assemble(context, :attr_key, [{:symbol, :=} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:attr_assignment, rest)
  end

  # TODO: test
  def assemble(context, :attr_assignment, [{:symbol, :"\""} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_node_type(:attribute_value_text)
    |> assemble(:text, rest)
  end

  # TODO: test
  def assemble(context, :attr_assignment, [{:symbol, :"{"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_node_type(:attribute_value_expression)
    |> assemble(:expression, rest)
  end

  defp add_attr_value_part(context, type) do
    part = {type, TokenHTMLEncoder.encode(context.token_buffer)}
    %{context | attr_value: context.attr_value ++ [part]}
  end

  defp add_end_tag(context) do
    new_tag = {:end_tag, context.tag_name}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_expression_tag(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    new_processed_tags = processed_tags ++ [{:expression, TokenHTMLEncoder.encode(token_buffer)}]
    %{context | processed_tags: new_processed_tags}
  end

  defp add_processed_token(%{processed_tokens: processed_tokens} = context, token) do
    %{context | processed_tokens: processed_tokens ++ [token]}
  end

  defp add_self_closing_tag(context) do
    new_tag = {:self_closing_tag, {context.tag_name, context.attrs}}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_start_tag(context) do
    new_tag = {:start_tag, {context.tag_name, context.attrs}}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp assemble_expression(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> assemble(:expression, rest)
  end

  defp assemble_text(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> assemble(:text, rest)
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

  defp error_reason(context, status, token)

  defp error_reason( _, :text, {:symbol, :<}) do
    """
    Unescaped '<' character inside text node.
    To escape use HTML entity: '&lt;'\
    """
  end

  defp error_reason( _, :text, {:symbol, :>}) do
    """
    Unescaped '>' character inside text node.
    To escape use HTML entity: '&gt;'\
    """
  end

  # # TODO: test
  defp error_reason(%{double_quote_open?: true}, :text_interpolation, nil) do
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

  defp flush_attribute(context) do
    new_attr = {context.attr_key, context.attr_value}
    %{context | attr_key: nil, attr_value: [], attrs: context.attrs ++ [new_attr]}
  end

  defp handle_attr_value_end(context, part_type, token, rest) do
    context
    |> add_attr_value_part(part_type)
    |> flush_attribute()
    |> set_node_type(:element_node)
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  defp handle_start_tag_end(context, token, rest) do
    type = Helpers.tag_type(context.tag_name)

    if type == :component || is_self_closing_tag?(context.tag_name) do
      add_self_closing_tag(context)
    else
      add_start_tag(context)
    end
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:text, rest)
  end

  defp increment_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces + 1}
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

  defp maybe_add_text(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    if Enum.any?(token_buffer) do
      new_processed_tags = processed_tags ++ [{:text, TokenHTMLEncoder.encode(token_buffer)}]
      %{context | processed_tags: new_processed_tags}
    else
      context
    end
  end

  defp open_double_quote(context) do
    %{context | double_quote_open?: true}
  end

  defp raise_error(%{processed_tokens: processed_tokens} = context, status, token, rest) do
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

    reason = error_reason(context, status, token)

    message = """


    #{reason}

    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^

    status = #{inspect(status)}

    context = #{inspect(context)}
    """

    raise SyntaxError, message: message
  end

  defp reset_attr_value(context) do
    %{context | attr_value: []}
  end

  defp reset_attrs(context) do
    %{context | attrs: []}
  end

  defp reset_braces(context) do
    %{context | num_open_braces: 0}
  end

  defp reset_double_quotes(context) do
    %{context | double_quote_open?: false}
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end

  defp set_attr_key(context, key) do
    %{context | attr_key: key}
  end

  defp set_node_type(context, type) do
    %{context | node_type: type}
  end

  defp set_tag_name(context, tag_name) do
    %{context | tag_name: tag_name}
  end









  # TO REFACTOR

  # def assemble([token | rest], type, context, _) do
  #   raise_error(context, type, token, rest)
  # end

  # def assemble([], type, context, _) do
  #   raise_error(context, type, nil, [])
  # end
end
