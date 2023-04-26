defmodule Hologram.Template.Parser do
  if Application.compile_env(:hologram, :debug_parser) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Template.Parser, :parse, 3} => [
          on_success: {Hologram.Template.Parser, :debug, 3},
          on_error: {Hologram.Template.Parser, :debug, 3}
        ]
      }
  end

  alias Hologram.Template.Helpers
  alias Hologram.Template.SyntaxError
  alias Hologram.Template.Tokenizer

  @type parsed_tag ::
          {:block_end | :block_start | :end_tag | :expression | :self_closing_tag,
           :start_tag | :text, any}

  @type status ::
          :attribute_assignment
          | :attribute_name
          | :block_end
          | :block_start
          | :end_tag
          | :end_tag_name
          | :expression
          | :text
          | :start_tag
          | :start_tag_name

  defmodule Context do
    alias Hologram.Template.Parser

    defstruct attribute_name: nil,
              attribute_value: [],
              attributes: [],
              block_name: nil,
              delimiter_stack: [],
              node_type: :text,
              prev_status: nil,
              processed_tags: [],
              processed_tokens: [],
              raw?: false,
              script?: false,
              tag_name: nil,
              token_buffer: []

    @type attribute_value_part :: list({:expression | :text, String.t()})

    @type delimiter ::
            :backtick
            | :curly_bracket
            | :double_quote
            | :ex_interpolation
            | :js_interpolation
            | :single_quote

    @type t :: %__MODULE__{
            attribute_name: String.t() | nil,
            attribute_value: list(attribute_value_part),
            attributes: list({String.t(), list(attribute_value_part())}),
            block_name: String.t(),
            delimiter_stack: list(delimiter),
            node_type: :attribute | :block | :tag | :text,
            prev_status: Parser.status(),
            processed_tags: [],
            processed_tokens: list(Tokenizer.token()),
            raw?: boolean,
            script?: boolean,
            tag_name: String.t(),
            token_buffer: list(Tokenizer.token())
          }
  end

  @intercept true
  @spec parse(%Context{}, status, list(Tokenizer.token())) :: list(parsed_tag)
  def parse(context \\ %Context{}, status \\ :text, tokens)

  def parse(context, :text, []) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> Map.get(:processed_tags)
  end

  def parse(context, :text, [{:whitespace, _value} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:string, _value} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "="} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(%{node_type: :attribute} = context, :text, [{:symbol, "\""} = token | rest]) do
    context
    |> add_attribute_value_part(:text)
    |> flush_attr()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> parse(:start_tag, rest)
  end

  def parse(%{script?: true, delimiter_stack: [:double_quote | _tail]} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_text(token, rest)
  end

  def parse(%{script?: true, delimiter_stack: []} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> open_double_quote()
    |> parse_text(token, rest)
  end

  def parse(context, :text, [{:symbol, "\""} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(%{script?: true, delimiter_stack: [:single_quote | _tail]} = context, :text, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_text(token, rest)
  end

  def parse(%{script?: true, delimiter_stack: []} = context, :text, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> open_single_quote()
    |> parse_text(token, rest)
  end

  def parse(context, :text, [{:symbol, "'"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "\\"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "/"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "\\{"} | rest]) do
    parse_text(context, {:symbol, "{"}, rest)
  end

  def parse(%{raw?: false} = context, :text, [{:symbol, "{#raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> enable_raw_mode()
    |> parse(:text, rest)
  end

  def parse(%{raw?: true} = context, :text, [{:symbol, "{#"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "{#"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:block)
    |> parse(:block_start, rest)
  end

  def parse(%{raw?: true} = context, :text, [{:symbol, "{/raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> disable_raw_mode()
    |> parse(:text, rest)
  end

  def parse(%{raw?: true} = context, :text, [{:symbol, "{/"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "{/"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> parse(:block_end, rest)
  end

  def parse(%{raw?: true} = context, :text, [{:symbol, "{"} | rest]) do
    parse_text(context, {:symbol, "{"}, rest)
  end

  def parse(%{node_type: :attribute} = context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> add_attribute_value_part(:text)
    |> reset_delimiter_stack()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> parse_expression(token, rest)
  end

  def parse(context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_delimiter_stack()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> parse_expression(token, rest)
  end

  def parse(context, :text, [{:symbol, "\\}"} | rest]) do
    parse_text(context, {:symbol, "}"}, rest)
  end

  def parse(%{raw?: true} = context, :text, [{:symbol, "}"} | rest]) do
    parse_text(context, {:symbol, "}"}, rest)
  end

  def parse(%{script?: true, delimiter_stack: [delimiter | _tail]} = context, :text, [
        {:symbol, "</"} = token | rest
      ])
      when delimiter in [:double_quote, :single_quote] do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "</"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> parse(:end_tag_name, rest)
  end

  def parse(%{script?: true} = context, :text, [{:symbol, "<"} = token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "<"} = token | [{:string, _value} | _tokens] = rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> parse(:start_tag_name, rest)
  end

  def parse(%{script?: true} = context, :text, [token | rest]) do
    parse_text(context, token, rest)
  end

  def parse(context, :text, [{:symbol, "<"} = token | rest]) do
    raise_error(context, :text, token, rest)
  end

  def parse(context, :text, [{:symbol, ">"} = token | rest]) do
    raise_error(context, :text, token, rest)
  end

  def parse(context, :start_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> reset_attributes()
    |> set_tag_name(tag_name)
    |> maybe_enable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:start_tag_name)
    |> parse(:start_tag, rest)
  end

  def parse(context, :start_tag, [{:whitespace, _} = token | rest]) do
    context
    |> add_processed_token(token)
    |> parse(:start_tag, rest)
  end

  def parse(context, :start_tag, [{:string, str} = token | rest]) do
    context
    |> set_attribute_name(str)
    |> reset_attribute_value()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:start_tag)
    |> parse(:attribute_name, rest)
  end

  def parse(context, :start_tag, [{:symbol, "/>"} = token | rest]) do
    handle_start_tag_end(context, token, rest, true)
  end

  def parse(context, :start_tag, [{:symbol, ">"} = token | rest]) do
    handle_start_tag_end(context, token, rest, false)
  end

  def parse(context, :end_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> set_tag_name(tag_name)
    |> maybe_disable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:end_tag_name)
    |> parse(:end_tag, rest)
  end

  def parse(context, :end_tag, [{:whitespace, _value} = token | rest]) do
    context
    |> add_processed_token(token)
    |> parse(:end_tag, rest)
  end

  def parse(context, :end_tag, [{:symbol, ">"} = token | rest]) do
    context
    |> add_end_tag()
    |> add_processed_token(token)
    |> set_prev_status(:end_tag)
    |> set_node_type(:text)
    |> parse(:text, rest)
  end

  def parse(context, :attribute_name, [{:whitespace, _value} = token | rest]) do
    context
    |> flush_attr()
    |> add_processed_token(token)
    |> set_prev_status(:attribute_name)
    |> parse(:start_tag, rest)
  end

  def parse(context, :attribute_name, [{:symbol, ">"} = token | rest]) do
    context
    |> flush_attr()
    |> handle_start_tag_end(token, rest, false)
  end

  def parse(context, :attribute_name, [{:symbol, "="} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attribute_name)
    |> set_node_type(:attribute)
    |> parse(:attribute_assignment, rest)
  end

  def parse(context, :attribute_assignment, [{:symbol, "\""} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attribute_assignment)
    |> parse(:text, rest)
  end

  def parse(%{raw?: true} = context, :attribute_assignment, [{:symbol, "{"} = token | rest]) do
    raise_error(context, :attribute_assignment, token, rest)
  end

  def parse(context, :attribute_assignment, [{:symbol, "{"} = token | rest]) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> set_prev_status(:attribute_assignment)
    |> parse(:expression, rest)
  end

  def parse(context, :block_start, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> buffer_token({:symbol, "{"})
    |> set_prev_status(:block_start)
    |> parse(:expression, rest)
  end

  def parse(context, :block_end, [{:string, block_name} = token | rest]) do
    context
    |> set_block_name(block_name)
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> parse(:block_end, rest)
  end

  def parse(context, :block_end, [{:symbol, "}"} = token | rest]) do
    context
    |> add_block_end()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:block_end)
    |> parse(:text, rest)
  end

  def parse(%{delimiter_stack: [:double_quote | _tail]} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse(%{delimiter_stack: [:single_quote | _tail]} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    parse_expression(context, token, rest)
  end

  def parse(context, :expression, [{:symbol, "\""} = token | rest]) do
    context
    |> open_double_quote()
    |> parse_expression(token, rest)
  end

  def parse(%{delimiter_stack: [:double_quote | _tail]} = context, :expression, [
        {:symbol, "'"} = token | rest
      ]) do
    parse_expression(context, token, rest)
  end

  def parse(%{delimiter_stack: [:single_quote | _tail]} = context, :expression, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse(context, :expression, [{:symbol, "'"} = token | rest]) do
    context
    |> open_single_quote()
    |> parse_expression(token, rest)
  end

  def parse(%{delimiter_stack: [:ex_interpolation | _tail]} = context, :expression, [
        {:symbol, "{"} = token | rest
      ]) do
    context
    |> open_curly_bracket()
    |> parse_expression(token, rest)
  end

  def parse(%{delimiter_stack: []} = context, :expression, [{:symbol, "{"} = token | rest]) do
    context
    |> open_curly_bracket()
    |> parse_expression(token, rest)
  end

  def parse(%{delimiter_stack: [], node_type: :text} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> buffer_token(token)
    |> add_expression_tag()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> parse(:text, rest)
  end

  def parse(
        %{delimiter_stack: [], node_type: :attribute, prev_status: :text} = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attribute_value_part(:expression)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> parse(:text, rest)
  end

  def parse(
        %{delimiter_stack: [], node_type: :attribute, prev_status: :attribute_assignment} =
          context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attribute_value_part(:expression)
    |> flush_attr()
    |> set_prev_status(:expression)
    |> parse(:start_tag, rest)
  end

  def parse(%{delimiter_stack: [], node_type: :block} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> buffer_token(token)
    |> add_block_start()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> set_node_type(:text)
    |> parse(:text, rest)
  end

  def parse(%{delimiter_stack: [:curly_bracket | _tail]} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse(context, :expression, [token | rest]) do
    parse_expression(context, token, rest)
  end

  # @doc """
  # Prints debug info for intercepted parse/3 calls.
  # """
  @spec debug({module, atom, list}, list | %FunctionClauseError{}, integer) :: :ok
  def debug({_module, _function, [context, status, tokens] = _args}, result, _start_timestamp) do
    # credo:disable-for-lines:13 /Credo.Check.Refactor.IoPuts|Credo.Check.Warning.IoInspect/
    IO.puts("\nPARSER..................................\n")
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

  defp add_attribute_value_part(context, type) do
    part = {type, join_tokens(context.token_buffer)}
    %{context | attribute_value: context.attribute_value ++ [part]}
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
    new_tag = {:self_closing_tag, {context.tag_name, context.attributes}}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp add_start_tag(context) do
    new_tag = {:start_tag, {context.tag_name, context.attributes}}
    %{context | processed_tags: context.processed_tags ++ [new_tag]}
  end

  defp buffer_token(%{token_buffer: token_buffer} = context, token) do
    %{context | token_buffer: token_buffer ++ [token]}
  end

  defp disable_raw_mode(context) do
    %{context | raw?: false}
  end

  defp disable_script_mode(context) do
    %{context | script?: false}
  end

  defp enable_raw_mode(context) do
    %{context | raw?: true}
  end

  defp enable_script_mode(context) do
    %{context | script?: true}
  end

  defp encode_tokens(tokens) do
    Enum.map(tokens, fn {_type, value} -> value end)
    |> Enum.join("")
  end

  defp escape_non_printable_chars(str) do
    str
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp error_reason_and_hint(context, status, token)

  defp error_reason_and_hint(context, :attribute_assignment, {:symbol, "{"}) do
    tag_type = Helpers.tag_type(context.tag_name)
    node_name = if tag_type == :element, do: "attribute", else: "property"

    """
    Reason:
    Expression #{node_name} value inside raw block detected.

    Hint:
    Either wrap the #{node_name} value with double quotes or remove the parent raw block".
    """
  end

  defp error_reason_and_hint(_context, :text, {:symbol, "<"}) do
    """
    Reason:
    Unescaped '<' character inside text node.

    Hint:
    To escape use HTML entity: '&lt;'.
    """
  end

  defp error_reason_and_hint(_context, :text, {:symbol, ">"}) do
    """
    Reason:
    Unescaped '>' character inside text node.

    Hint:
    To escape use HTML entity: '&gt;'.
    """
  end

  defp flush_attr(context) do
    new_attr = {context.attribute_name, context.attribute_value}

    %{
      context
      | attribute_name: nil,
        attribute_value: [],
        attributes: context.attributes ++ [new_attr]
    }
  end

  defp handle_start_tag_end(context, token, rest, self_closing?) do
    tag_type = Helpers.tag_type(context.tag_name)

    add_tag_fun =
      if (tag_type == :component && self_closing?) || Helpers.void_element?(context.tag_name) do
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
    |> parse(:text, rest)
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
    disable_script_mode(context)
  end

  defp maybe_disable_script_mode(context, _tag_name), do: context

  defp maybe_enable_script_mode(context, "script") do
    context
    |> enable_script_mode()
    |> reset_delimiter_stack()
  end

  defp maybe_enable_script_mode(context, _tag_name), do: context

  defp open_curly_bracket(context) do
    %{context | delimiter_stack: [:curly_bracket | context.delimiter_stack]}
  end

  defp open_double_quote(context) do
    %{context | delimiter_stack: [:double_quote | context.delimiter_stack]}
  end

  defp open_single_quote(context) do
    %{context | delimiter_stack: [:single_quote | context.delimiter_stack]}
  end

  defp parse_expression(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse(:expression, rest)
  end

  defp parse_text(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse(:text, rest)
  end

  defp pop_delimiter_stack(%{delimiter_stack: [_head | tail]} = context) do
    %{context | delimiter_stack: tail}
  end

  defp raise_error(%{processed_tokens: processed_tokens} = context, status, token, rest) do
    processed_tokens_str = encode_tokens(processed_tokens)
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
      [token]
      |> encode_tokens()
      |> escape_non_printable_chars()

    next_fragment =
      rest
      |> encode_tokens()
      |> String.slice(0, 20)
      |> escape_non_printable_chars()

    reason_and_hint = error_reason_and_hint(context, status, token)

    message = """


    #{reason_and_hint}
    #{prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^

    status = #{inspect(status)}

    token = #{inspect(token)}

    context = #{inspect(context)}
    """

    raise SyntaxError, message: message
  end

  defp reset_attribute_value(context) do
    %{context | attribute_value: []}
  end

  defp reset_attributes(context) do
    %{context | attributes: []}
  end

  defp reset_delimiter_stack(context) do
    %{context | delimiter_stack: []}
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end

  defp set_attribute_name(context, name) do
    %{context | attribute_name: name}
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

  # parse(context, type, [token | rest]) do
  #   raise_error(context, type, token, rest)
  # end

  # parse(context, type, []) do
  #   raise_error(context, type, nil, [])
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
end
