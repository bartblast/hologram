defmodule Hologram.Template.TagAssembler do
  if Application.compile_env(:hologram, :debug_tag_assembler) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Template.TagAssembler, :assemble, 3} => [
          after: {Hologram.Template.TagAssembler, :debug, 2}
        ]
      }
  end

  alias Hologram.Template.Helpers

  @initial_context %{
    attr_name: nil,
    attr_value: [],
    attrs: [],
    block_expression: nil,
    block_name: nil,
    double_quote_open?: false,
    node_type: :text,
    num_open_curly_brackets: 0,
    prev_status: nil,
    processed_tags: [],
    processed_tokens: [],
    raw?: false,
    script?: false,
    tag_name: nil,
    token_buffer: []
  }

  @intercept true
  def assemble(context \\ @initial_context, status \\ :text, tokens)

  def assemble(context, :text, []) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> Map.get(:processed_tags)
  end

  def assemble(context, :text, [{:whitespace, _value} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:string, _value} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "="} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(%{node_type: :attribute} = context, :text, [{:symbol, "\""} = token | rest]) do
    context
    |> add_attr_value_part(:text)
    |> flush_attr()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> assemble(:start_tag, rest)
  end

  def assemble(%{double_quote_open?: false, script?: true} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> open_double_quote()
    |> assemble_text(token, rest)
  end

  def assemble(%{double_quote_open?: true, script?: true} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> close_double_quote()
    |> assemble_text(token, rest)
  end

  def assemble(context, :text, [{:symbol, "\""} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "\\"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "/"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "\\{"} | rest]) do
    assemble_text(context, {:symbol, "{"}, rest)
  end

  def assemble(%{raw?: false} = context, :text, [{:symbol, "{#raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> enable_raw_mode()
    |> assemble(:text, rest)
  end

  def assemble(%{raw?: true} = context, :text, [{:symbol, "{#"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "{#"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:block)
    |> assemble(:block_start, rest)
  end

  def assemble(%{raw?: true} = context, :text, [{:symbol, "{/raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> disable_raw_mode()
    |> assemble(:text, rest)
  end

  def assemble(%{raw?: true} = context, :text, [{:symbol, "{/"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "{/"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> assemble(:block_end, rest)
  end

  def assemble(%{raw?: true} = context, :text, [{:symbol, "{"} | rest]) do
    assemble_text(context, {:symbol, "{"}, rest)
  end

  def assemble(%{node_type: :attribute} = context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> add_attr_value_part(:text)
    |> reset_double_quotes()
    |> reset_braces()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> assemble_expression(token, rest)
  end

  def assemble(context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_double_quotes()
    |> reset_braces()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> assemble_expression(token, rest)
  end

  def assemble(context, :text, [{:symbol, "\\}"} | rest]) do
    assemble_text(context, {:symbol, "}"}, rest)
  end

  def assemble(%{raw?: true} = context, :text, [{:symbol, "}"} | rest]) do
    assemble_text(context, {:symbol, "}"}, rest)
  end

  def assemble(%{double_quote_open?: true, script?: true} = context, :text, [
        {:symbol, "</"} = token | rest
      ]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "</"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> assemble(:end_tag_name, rest)
  end

  def assemble(%{script?: true} = context, :text, [{:symbol, "<"} = token | rest]) do
    assemble_text(context, token, rest)
  end

  def assemble(context, :text, [{:symbol, "<"} = token | [{:string, _value} | _tokens] = rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> assemble(:start_tag_name, rest)
  end

  def assemble(%{script?: true} = context, :text, [token | rest]) do
    assemble_text(context, token, rest)
  end

  # assemble(context, :text, [{:symbol, :<} = token | rest]) do
  #   raise_error(context, :text, token, rest)
  # end

  # assemble(context, :text, [{:symbol, :>} = token | rest]) do
  #   raise_error(context, :text, token, rest)
  # end

  def assemble(context, :start_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> reset_attrs()
    |> set_tag_name(tag_name)
    |> maybe_enable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:start_tag_name)
    |> assemble(:start_tag, rest)
  end

  def assemble(context, :start_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:start_tag, rest)
  end

  def assemble(context, :start_tag, [{:string, str} = token | rest]) do
    context
    |> set_attr_name(str)
    |> reset_attr_value()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:start_tag)
    |> assemble(:attr_name, rest)
  end

  def assemble(context, :start_tag, [{:symbol, "/>"} = token | rest]) do
    handle_start_tag_end(context, token, rest, true)
  end

  def assemble(context, :start_tag, [{:symbol, ">"} = token | rest]) do
    handle_start_tag_end(context, token, rest, false)
  end

  def assemble(context, :end_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> set_tag_name(tag_name)
    |> maybe_disable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:end_tag_name)
    |> assemble(:end_tag, rest)
  end

  def assemble(context, :end_tag, [{:whitespace, _value} = token | rest]) do
    context
    |> add_processed_token(token)
    |> assemble(:end_tag, rest)
  end

  def assemble(context, :end_tag, [{:symbol, ">"} = token | rest]) do
    context
    |> add_end_tag()
    |> add_processed_token(token)
    |> set_prev_status(:end_tag)
    |> set_node_type(:text)
    |> assemble(:text, rest)
  end

  def assemble(context, :attr_name, [{:whitespace, _value} = token | rest]) do
    context
    |> flush_attr()
    |> add_processed_token(token)
    |> set_prev_status(:attr_name)
    |> assemble(:start_tag, rest)
  end

  def assemble(context, :attr_name, [{:symbol, ">"} = token | rest]) do
    context
    |> flush_attr()
    |> handle_start_tag_end(token, rest, false)
  end

  def assemble(context, :attr_name, [{:symbol, "="} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attr_name)
    |> set_node_type(:attribute)
    |> assemble(:attr_assignment, rest)
  end

  def assemble(context, :attr_assignment, [{:symbol, "\""} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attr_assignment)
    |> assemble(:text, rest)
  end

  def assemble(context, :attr_assignment, [{:symbol, "{"} = token | rest]) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> set_prev_status(:attr_assignment)
    |> assemble(:expression, rest)
  end

  def assemble(context, :block_start, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> buffer_token({:symbol, "{"})
    |> set_prev_status(:block_start)
    |> assemble(:expression, rest)
  end

  def assemble(context, :block_end, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> assemble(:block_end, rest)
  end

  def assemble(context, :block_end, [{:symbol, "}"} = token | rest]) do
    context
    |> add_block_end()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:block_end)
    |> assemble(:text, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> open_double_quote()
    |> assemble_expression(token, rest)
  end

  def assemble(%{double_quote_open?: true} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> close_double_quote()
    |> assemble_expression(token, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [
        {:symbol, "{"} = token | rest
      ]) do
    context
    |> increment_num_open_curly_brackets()
    |> assemble_expression(token, rest)
  end

  def assemble(
        %{double_quote_open?: false, node_type: :text, num_open_curly_brackets: 0} = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_expression_tag()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> assemble(:text, rest)
  end

  def assemble(
        %{
          double_quote_open?: false,
          node_type: :attribute,
          num_open_curly_brackets: 0,
          prev_status: :text
        } = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attr_value_part(:expression)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> assemble(:text, rest)
  end

  def assemble(
        %{
          double_quote_open?: false,
          node_type: :attribute,
          num_open_curly_brackets: 0,
          prev_status: :attr_assignment
        } = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attr_value_part(:expression)
    |> flush_attr()
    |> set_prev_status(:expression)
    |> assemble(:start_tag, rest)
  end

  def assemble(
        %{double_quote_open?: false, node_type: :block, num_open_curly_brackets: 0} = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_block_start()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> set_node_type(:text)
    |> assemble(:text, rest)
  end

  def assemble(%{double_quote_open?: false} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> decrement_num_open_curly_brackets()
    |> assemble_expression(token, rest)
  end

  def assemble(context, :expression, [token | rest]) do
    assemble_expression(context, token, rest)
  end

  # @doc """
  # Prints debug info for intercepted assemble/3 calls.
  # """
  @spec debug({module, atom, list}, list) :: :ok
  def debug({_module, _function, [context, status, tokens] = _args}, result) do
    # credo:disable-for-lines:13 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("\nASSEMBLE................................\n")
    IO.puts("context")
    IO.inspect(context)
    IO.puts("")
    IO.puts("status")
    IO.inspect(status)
    IO.puts("")
    IO.puts("tokens")
    IO.inspect(tokens)
    IO.puts("")
    IO.puts("result")
    IO.inspect(result)
    IO.puts("\n........................................\n")
  end

  defp add_attr_value_part(context, type) do
    part = {type, join_tokens(context.token_buffer)}
    %{context | attr_value: context.attr_value ++ [part]}
  end

  defp add_block_start(context) do
    expression = join_tokens(context.token_buffer)
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

  defp buffer_token(%{token_buffer: token_buffer} = context, token) do
    %{context | token_buffer: token_buffer ++ [token]}
  end

  defp close_double_quote(context) do
    %{context | double_quote_open?: false}
  end

  defp decrement_num_open_curly_brackets(context) do
    %{context | num_open_curly_brackets: context.num_open_curly_brackets - 1}
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
    |> set_prev_status(:start_tag)
    |> set_node_type(:text)
    |> assemble(:text, rest)
  end

  defp increment_num_open_curly_brackets(context) do
    %{context | num_open_curly_brackets: context.num_open_curly_brackets + 1}
  end

  defp join_tokens(tokens) do
    Enum.map(tokens, fn {_type, value} -> value end)
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

  defp maybe_disable_script_mode(context, _tag_name), do: context

  defp maybe_enable_script_mode(context, "script") do
    %{context | script?: true}
    |> reset_double_quotes()
  end

  defp maybe_enable_script_mode(context, _tag_name), do: context

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
    %{context | num_open_curly_brackets: 0}
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

  defp set_node_type(context, type) do
    %{context | node_type: type}
  end

  defp set_prev_status(context, status) do
    %{context | prev_status: status}
  end

  defp set_tag_name(context, name) do
    %{context | tag_name: name}
  end

  # TODO: cleanup

  # alias Hologram.Template.SyntaxError

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
end
