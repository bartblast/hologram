defmodule Hologram.Template.TagAssembler do
  require Hologram.Template.Macros
  import Hologram.Template.Macros
  alias Hologram.Template.Helpers

  @initial_context %{
    attr_name: nil,
    attr_value: [],
    attrs: [],
    block_expression: nil,
    block_name: nil,
    double_quote_open?: false,
    num_open_braces: 0,
    prev_status: nil,
    processed_tags: [],
    processed_tokens: [],
    raw?: false,
    tag_name: nil,
    token_buffer: []
  }

  def assemble(context \\ @initial_context, status \\ :text, tokens)

  assemble(context, :text, []) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> Map.get(:processed_tags)
  end

  assemble(context, :text, [{:whitespace, _} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(context, :text, [{:string, _} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(context, :text, [{:symbol, "="} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(%{prev_status: :attribute_assignment} = context, :text, [{:symbol, "\""} = token | rest]) do
    context
    |> add_attr_value_part(:text)
    |> flush_attr()
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  assemble(context, :text, [{:symbol, "\""} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(context, :text, [{:symbol, "\\"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(context, :text, [{:symbol, "/"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  assemble(context, :text, [{:symbol, "\\{"} | rest]) do
    assemble_text(context, {:symbol, "{"}, rest)
  end

  assemble(%{raw?: false} = context, :text, [{:symbol, "{#raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> enable_raw_mode()
    |> assemble(:text, rest)
  end

  assemble(%{raw?: true} = context, :text, [{:symbol, "{#"} = token | rest]) do
    assemble_text(context, {:symbol, "{#"}, rest)
  end

  assemble(context, :text, [{:symbol, "{#"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> assemble(:block_start, rest)
  end

  assemble(%{raw?: true} = context, :text, [{:symbol, "{/raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> disable_raw_mode()
    |> assemble(:text, rest)
  end

  assemble(%{raw?: true} = context, :text, [{:symbol, "{/"} = token | rest]) do
    assemble_text(context, {:symbol, "{/"}, rest)
  end

  assemble(context, :text, [{:symbol, "{/"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> assemble(:block_end, rest)
  end

  assemble(%{raw?: true} = context, :text, [{:symbol, "{"} | rest]) do
    assemble_text(context, {:symbol, "{"}, rest)
  end

  # assemble(%{node_type: :attribute_value_text} = context, :text, [{:symbol, :"{"} = token | rest]) do
  #   context
  #   |> add_attr_value_part(:literal)
  #   |> reset_double_quotes()
  #   |> reset_braces()
  #   |> reset_token_buffer()
  #   |> assemble_expression(token, rest)
  # end

  assemble(context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_double_quotes()
    |> reset_braces()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> add_processed_token(token)
    |> assemble(:expression, rest)
  end

  assemble(context, :text, [{:symbol, "\\}"} | rest]) do
    assemble_text(context, {:symbol, "}"}, rest)
  end

  assemble(%{raw?: true} = context, :text, [{:symbol, "}"} | rest]) do
    assemble_text(context, {:symbol, "}"}, rest)
  end

  # # TODO: test
  # assemble(%{script?: true} = context, :text, [{:symbol, :"</"} | rest]) do
  #   assemble_text(context, {:symbol, :"</"}, rest)
  # end

  assemble(context, :text, [{:symbol, "</"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:end_tag_name, rest)
  end

  # # TODO: test
  # assemble(%{script?: true} = context, :text, [{:symbol, :"<"} | rest]) do
  #   assemble_text(context, {:symbol, :"<"}, rest)
  # end

  assemble(context, :text, [{:symbol, "<"} = token | [{:string, _} | _] = rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:start_tag_name, rest)
  end

  # assemble(context, :text, [{:symbol, :<} = token | rest]) do
  #   raise_error(context, :text, token, rest)
  # end

  # # TODO: test
  # assemble(%{script?: true} = context, :text, [{:symbol, :>} | rest]) do
  #   assemble_text(context, {:symbol, :>}, rest)
  # end

  # assemble(context, :text, [{:symbol, :>} = token | rest]) do
  #   raise_error(context, :text, token, rest)
  # end

  # TODO: test
  assemble(context, :start_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> reset_attrs()
    |> set_tag_name(tag_name)
    |> maybe_enable_script_mode(tag_name)
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  assemble(context, :start_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  # TODO: test
  assemble(context, :start_tag, [{:string, str} = token | rest]) do
    context
    |> set_attr_name(str)
    |> reset_attr_value()
    # |> reset_double_quotes()
    # |> reset_braces()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:attr_name, rest)
  end

  assemble(context, :start_tag, [{:symbol, "/>"} = token | rest]) do
    handle_start_tag_end(context, token, rest, true)
  end

  assemble(context, :start_tag, [{:symbol, ">"} = token | rest]) do
    handle_start_tag_end(context, token, rest, false)
  end

  # TODO: test
  assemble(context, :end_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> set_tag_name(tag_name)
    |> maybe_disable_script_mode(tag_name)
    |> add_processed_token(token)
    |> assemble(:end_tag, rest)
  end

  assemble(context, :end_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:end_tag, rest)
  end

  assemble(context, :end_tag, [{:symbol, ">"} = token | rest]) do
    context
    |> add_end_tag()
    |> add_processed_token(token)
    |> assemble(:text, rest)
  end

  # TODO: test
  assemble(context, :attr_name, [{:whitespace, _} = token | rest]) do
    context
    |> flush_attr()
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  # TODO: test
  assemble(context, :attr_name, [{:symbol, ">"} = token | rest]) do
    context
    |> flush_attr()
    |> handle_start_tag_end(token, rest, false)
  end

  # TODO: test
  assemble(context, :attr_name, [{:symbol, "="} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:attr_assignment, rest)
  end

  # TODO: test
  assemble(context, :attr_assignment, [{:symbol, "\""} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attribute_assignment)
    |> assemble(:text, rest)
  end

  # TODO: test
  assemble(context, :block_start, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:block_start)
    |> assemble(:expression, rest)
  end

  # TODO: test
  assemble(context, :block_end, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:block_end, rest)
  end

  # TODO: test
  assemble(context, :block_end, [{:symbol, "}"} = token | rest]) do
    context
    |> add_block_end()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:text, rest)
  end

  assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, "\""} = token | rest]) do
    context
    |> open_double_quote()
    |> assemble_expression(token, rest)
  end

  assemble(%{double_quote_open?: true} = context, :expression, [{:symbol, "\""} = token | rest]) do
    context
    |> close_double_quote()
    |> assemble_expression(token, rest)
  end

  assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, "{"} = token | rest]) do
    context
    |> increment_num_open_braces()
    |> assemble_expression(token, rest)
  end

  assemble(
    %{double_quote_open?: false, num_open_braces: 0, prev_status: :text} = context,
    :expression,
    [{:symbol, "}"} = token | rest]
  ) do
    context
    |> add_expression_tag()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:text, rest)
  end

  # TODO: test
  assemble(
    %{double_quote_open?: false, num_open_braces: 0, prev_status: :block_start} = context,
    :expression,
    [{:symbol, "}"} = token | rest]
  ) do
    context
    |> add_block_start()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:text, rest)
  end

  assemble(%{double_quote_open?: false} = context, :expression, [{:symbol, "}"} = token | rest]) do
    context
    |> decrement_num_open_braces()
    |> assemble_expression(token, rest)
  end

  assemble(context, :expression, [token | rest]) do
    assemble_expression(context, token, rest)
  end

  defp add_attr_value_part(context, type) do
    part = {type, join_tokens(context.token_buffer)}
    %{context | attr_value: context.attr_value ++ [part]}
  end

  defp add_block_start(context) do
    expression =
      context.token_buffer
      |> join_tokens()
      |> String.trim()

    new_tag = {:block_start, {context.block_name, expression}}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_block_end(context) do
    new_tag = {:block_end, context.block_name}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_end_tag(context) do
    new_tag = {:end_tag, context.tag_name}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_expression_tag(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    new_processed_tags = processed_tags ++ [{:expression, join_tokens(token_buffer)}]
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

  defp close_double_quote(context) do
    %{context | double_quote_open?: false}
  end

  defp buffer_token(%{token_buffer: token_buffer} = context, token) do
    %{context | token_buffer: token_buffer ++ [token]}
  end

  defp decrement_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces - 1}
  end

  defp disable_raw_mode(context) do
    %{context | raw?: false}
  end

  defp enable_raw_mode(context) do
    %{context | raw?: true}
  end

  defp flush_attr(context) do
    new_attr = {context.attr_name, context.attr_value}
    %{context | attr_name: nil, attr_value: [], attrs: context.attrs ++ [new_attr]}
  end

  defp handle_start_tag_end(context, token, rest, self_closing?) do
    type = Helpers.tag_type(context.tag_name)

    add_tag_fun =
      if (type == :component && self_closing?) || Helpers.void_element?(context.tag_name) do
        &add_self_closing_tag/1
      else
        &add_start_tag/1
      end

    context
    |> add_tag_fun.()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> assemble(:text, rest)
  end

  defp increment_num_open_braces(context) do
    %{context | num_open_braces: context.num_open_braces + 1}
  end

  defp join_tokens(tokens) do
    Enum.map(tokens, fn {_, str} -> str end)
    |> Enum.join("")
  end

  defp maybe_add_text_tag(%{token_buffer: token_buffer, processed_tags: processed_tags} = context) do
    if Enum.any?(token_buffer) do
      new_processed_tags = processed_tags ++ [{:text, join_tokens(token_buffer)}]
      %{context | processed_tags: new_processed_tags}
    else
      context
    end
  end

  defp maybe_disable_script_mode(context, "script") do
    %{context | script?: false}
  end

  defp maybe_disable_script_mode(context, _), do: context

  defp maybe_enable_script_mode(context, "script") do
    %{context | script?: true}
  end

  defp maybe_enable_script_mode(context, _), do: context

  defp open_double_quote(context) do
    %{context | double_quote_open?: true}
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

  defp set_attr_name(context, name) do
    %{context | attr_name: name}
  end

  defp set_block_name(context, name) do
    %{context | block_name: name}
  end

  defp set_prev_status(context, status) do
    %{context | prev_status: status}
  end

  defp set_tag_name(context, name) do
    %{context | tag_name: name}
  end








  # alias Hologram.Template.SyntaxError

  # @initial_context %{
  #   script?: false,
  # }

  # assemble(context, :text, [{:directive, :raw_start} = token | rest]) do
  #   context
  #   |> enable_raw_markup()
  #   |> add_processed_token(token)
  #   |> assemble(:text, rest)
  # end

  # assemble(context, :text, [{:directive, :raw_end} = token | rest]) do
  #   context
  #   |> disable_raw_markup()
  #   |> add_processed_token(token)
  #   |> assemble(:text, rest)
  # end














  # assemble(
  #   %{double_quote_open?: false, num_open_braces: 0, node_type: :attribute_value_expression} =
  #     context,
  #   :expression,
  #   [{:symbol, :"}"} = token | rest]
  # ) do
  #   handle_attr_value_end(context, :expression, token, rest)
  # end

  # assemble(
  #   %{double_quote_open?: false, num_open_braces: 0, node_type: :attribute_value_text} = context,
  #   :expression,
  #   [{:symbol, :"}"} = token | rest]
  # ) do
  #   context
  #   |> buffer_token(token)
  #   |> add_processed_token(token)
  #   |> add_attr_value_part(:expression)
  #   |> reset_token_buffer()
  #   |> assemble(:text, rest)
  # end

  # assemble(context, :attr_assignment, [{:symbol, :"{"} = token | rest]) do
  #   context
  #   |> buffer_token(token)
  #   |> add_processed_token(token)
  #   |> set_node_type(:attribute_value_expression)
  #   |> assemble(:expression, rest)
  # end

  # assemble(context, type, [token | rest]) do
  #   raise_error(context, type, token, rest)
  # end

  # assemble(context, type, []) do
  #   raise_error(context, type, nil, [])
  # end

  # defp error_reason(context, status, token)

  # defp error_reason(_, :text, {:symbol, :<}) do
  #   """
  #   Unescaped '<' character inside text node.
  #   To escape use HTML entity: '&lt;'\
  #   """
  # end

  # defp error_reason(_, :text, {:symbol, :>}) do
  #   """
  #   Unescaped '>' character inside text node.
  #   To escape use HTML entity: '&gt;'\
  #   """
  # end

  # defp error_reason(_, :start_tag, nil) do
  #   "Unclosed start tag."
  # end

  # defp error_reason(_, :start_tag, {:symbol, :=}) do
  #   "Missing attribute name."
  # end

  # defp error_reason(_, _, _) do
  #   "Unknown reason."
  # end

  # # TODO: test
  # defp escape_non_printable_chars(str) do
  #   str
  #   |> String.replace("\n", "\\n")
  #   |> String.replace("\r", "\\r")
  #   |> String.replace("\t", "\\t")
  # end

  # defp handle_attr_value_end(context, part_type, token, rest) do
  #   context =
  #     if part_type == :expression do
  #       buffer_token(context, token)
  #     else
  #       context
  #     end

  #   context
  #   |> add_attr_value_part(part_type)
  #   |> flush_attribute()
  #   |> set_node_type(:element_node)
  #   |> add_processed_token(token)
  #   |> assemble(:start_tag, rest)
  # end

  # defp raise_error(%{processed_tokens: processed_tokens} = context, status, token, rest) do
  #   processed_tokens_str = TokenHTMLEncoder.encode(processed_tokens)
  #   processed_tokens_len = String.length(processed_tokens_str)

  #   prev_fragment =
  #     if processed_tokens_len > 20 do
  #       String.slice(processed_tokens_str, -20..-1)
  #     else
  #       processed_tokens_str
  #     end
  #     |> escape_non_printable_chars()

  #   prev_fragment_len = String.length(prev_fragment)
  #   indent = String.duplicate(" ", prev_fragment_len)

  #   current_fragment =
  #     TokenHTMLEncoder.encode(token)
  #     |> escape_non_printable_chars()

  #   next_fragment =
  #     TokenHTMLEncoder.encode(rest)
  #     |> String.slice(0, 20)
  #     |> escape_non_printable_chars()

  #   reason = error_reason(context, status, token)

  #   message = """


  #   #{reason}

  #   #{prev_fragment}#{current_fragment}#{next_fragment}
  #   #{indent}^

  #   status = #{inspect(status)}

  #   token = #{inspect(token)}

  #   context = #{inspect(context)}
  #   """

  #   raise SyntaxError, message: message
  # end

  # defp set_node_type(context, type) do
  #   %{context | node_type: type}
  # end
end
