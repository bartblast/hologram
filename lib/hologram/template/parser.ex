defmodule Hologram.Template.Parser do
  @moduledoc false

  if Application.compile_env(:hologram, :debug_parser) do
    use Interceptor.Annotated,
      config: %{
        {Hologram.Template.Parser, :parse_tokens, 3} => [
          on_success: {Hologram.Template.Parser, :debug, 3},
          on_error: {Hologram.Template.Parser, :debug, 3}
        ]
      }
  end

  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser
  alias Hologram.Template.Tokenizer
  alias Hologram.TemplateSyntaxError

  @default_error_details """
  Reason:
  Unknown reason.

  Hint:
  Please report that you received this message here: https://github.com/bartblast/hologram/issues
  and include a markup snippet that will allow us to reproduce the issue.
  """

  @unescaped_lt_char_details """
  Reason:
  Unescaped '<' character inside text node.

  Hint:
  To escape use HTML entity: '&lt;'.
  """

  @type parsed_tag ::
          {:block_end
           | :block_start
           | :doctype
           | :end_tag
           | :expression
           | :public_comment_end
           | :public_comment_start
           | :self_closing_tag
           | :start_tag
           | :text, any}

  @type status ::
          :attribute_assignment
          | :attribute_name
          | :block_end
          | :block_start
          | :doctype
          | :end_tag
          | :end_tag_name
          | :expression
          | :text
          | :start_tag
          | :start_tag_name

  defmodule Context do
    @moduledoc false

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
            | :elixir_interpolation
            | :javascript_interpolation
            | :single_quote

    @type t :: %__MODULE__{
            attribute_name: String.t() | nil,
            attribute_value: list(attribute_value_part),
            attributes: list({String.t(), list(attribute_value_part())}),
            block_name: String.t() | nil,
            delimiter_stack: list(delimiter),
            node_type: :attribute | :block | :public_comment | :tag | :text,
            prev_status: Parser.status() | nil,
            processed_tags: [],
            processed_tokens: list(Tokenizer.token()),
            raw?: boolean,
            script?: boolean,
            tag_name: String.t() | nil,
            token_buffer: list(Tokenizer.token())
          }
  end

  @doc """
  Parses markup into tags.

  ## Examples

      iex> markup = "<div id=\"test\"></div>"
      iex> parse_markup(markup)
      [start_tag: {"div", [{"id", [text: "test"]}]}, end_tag: "div"]
  """
  @spec parse_markup(String.t()) :: list(parsed_tag)
  def parse_markup(markup) do
    markup
    |> Tokenizer.tokenize()
    |> parse_tokens()
  end

  @doc """
  Parses tokens into tags.

  ## Examples

      iex> tokens = [
      ...>   symbol: "<",
      ...>   string: "div",
      ...>   whitespace: " ",
      ...>   string: "id",
      ...>   symbol: "=",
      ...>   symbol: "\"",
      ...>   string: "test",
      ...>   symbol: "\"",
      ...>   symbol: ">",
      ...>   symbol: "</",
      ...>   string: "div",
      ...>   symbol: ">"
      ...> ]
      iex> parse_tokens(tokens)
      [start_tag: {"div", [{"id", [text: "test"]}]}, end_tag: "div"]
  """
  @intercept true
  @spec parse_tokens(Context.t(), status, list(Tokenizer.token())) :: list(parsed_tag)
  def parse_tokens(context \\ %Context{}, status \\ :text, tokens)

  # Note: try to keep the pattern matching order from Hologram.Template.Tokenizer where possible.

  # --- ATTRIBUTE ASSIGNMENT ---

  def parse_tokens(context, :attribute_assignment, [{:symbol, "\""} = token | rest]) do
    context
    |> add_processed_token(token)
    |> set_prev_status(:attribute_assignment)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{raw?: true} = context, :attribute_assignment, [{:symbol, "{"} = token | rest]) do
    tag_type = Helpers.tag_type(context.tag_name)
    node_name = if tag_type == :element, do: "attribute", else: "property"

    details = """
    Reason:
    Expression #{node_name} value inside raw block detected.

    Hint:
    Either wrap the #{node_name} value with double quotes or remove the parent raw block".
    """

    raise_error(details, context, :attribute_assignment, token, rest)
  end

  def parse_tokens(context, :attribute_assignment, [{:symbol, "{"} = token | rest]) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> set_prev_status(:attribute_assignment)
    |> push_delimiter_stack(:expression)
    |> parse_tokens(:expression, rest)
  end

  # --- ATTRIBUTE NAME ---

  def parse_tokens(context, :attribute_name, [{:whitespace, _value} = token | rest]) do
    context
    |> set_attribute_name()
    |> flush_attribute()
    |> add_processed_token(token)
    |> set_prev_status(:attribute_name)
    |> parse_tokens(:start_tag, rest)
  end

  def parse_tokens(context, :attribute_name, [{:symbol, "="} = token | rest]) do
    context
    |> set_attribute_name()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:attribute_name)
    |> set_node_type(:attribute)
    |> parse_tokens(:attribute_assignment, rest)
  end

  def parse_tokens(context, :attribute_name, [{:symbol, ">"} = token | rest]) do
    context
    |> set_attribute_name()
    |> flush_attribute()
    |> parse_start_tag_end(token, rest, false)
  end

  def parse_tokens(context, :attribute_name, [{:symbol, "-"} = token | rest]) do
    parse_attribute_name(context, token, rest)
  end

  def parse_tokens(context, :attribute_name, [{:string, _str} = token | rest]) do
    parse_attribute_name(context, token, rest)
  end

  # --- DOCTYPE ---

  def parse_tokens(context, :doctype, []) do
    details = """
    Reason:
    Unclosed DOCTYPE declaration.

    Hint:
    Close the DOCTYPE declaration with '>' character.
    """

    raise_error(details, context, :doctype, nil, [])
  end

  def parse_tokens(context, :doctype, [{:symbol, ">"} = token | rest]) do
    context
    |> add_doctype_declaration()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(context, :doctype, [token | rest]) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse_tokens(:doctype, rest)
  end

  # --- END TAG NAME ---

  def parse_tokens(context, :end_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> set_tag_name(tag_name)
    |> maybe_disable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:end_tag_name)
    |> parse_tokens(:end_tag, rest)
  end

  # --- END TAG ---

  def parse_tokens(context, :end_tag, [{:whitespace, _value} = token | rest]) do
    context
    |> add_processed_token(token)
    |> parse_tokens(:end_tag, rest)
  end

  def parse_tokens(context, :end_tag, [{:symbol, ">"} = token | rest]) do
    context
    |> add_end_tag()
    |> add_processed_token(token)
    |> set_prev_status(:end_tag)
    |> set_node_type(:text)
    |> parse_tokens(:text, rest)
  end

  # --- EXPRESSION ---

  def parse_tokens(%{delimiter_stack: [delimiter | _tail]} = context, :expression, [
        {:symbol, "\#{"} = token | rest
      ])
      when delimiter in [:double_quote, :single_quote] do
    context
    |> push_delimiter_stack(:elixir_interpolation)
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{delimiter_stack: [:double_quote | _tail]} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{delimiter_stack: [:single_quote | _tail]} = context, :expression, [
        {:symbol, "\""} = token | rest
      ]) do
    parse_expression(context, token, rest)
  end

  def parse_tokens(context, :expression, [{:symbol, "\""} = token | rest]) do
    context
    |> push_delimiter_stack(:double_quote)
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{delimiter_stack: [:double_quote | _tail]} = context, :expression, [
        {:symbol, "'"} = token | rest
      ]) do
    parse_expression(context, token, rest)
  end

  def parse_tokens(%{delimiter_stack: [:single_quote | _tail]} = context, :expression, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse_tokens(context, :expression, [{:symbol, "'"} = token | rest]) do
    context
    |> push_delimiter_stack(:single_quote)
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{delimiter_stack: [delimiter | _tail]} = context, :expression, [
        {:symbol, "{"} = token | rest
      ])
      when delimiter in [:double_quote, :single_quote] do
    parse_expression(context, token, rest)
  end

  def parse_tokens(context, :expression, [{:symbol, "{"} = token | rest]) do
    context
    |> push_delimiter_stack(:curly_bracket)
    |> parse_expression(token, rest)
  end

  def parse_tokens(
        %{
          delimiter_stack: [:expression],
          node_type: :attribute,
          prev_status: :attribute_assignment
        } = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attribute_value_part(:expression)
    |> flush_attribute()
    |> set_prev_status(:expression)
    |> pop_delimiter_stack()
    |> parse_tokens(:start_tag, rest)
  end

  def parse_tokens(
        %{delimiter_stack: [:expression], node_type: :attribute, prev_status: :text} = context,
        :expression,
        [{:symbol, "}"} = token | rest]
      ) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> add_attribute_value_part(:expression)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> pop_delimiter_stack()
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(
        %{delimiter_stack: [:expression | _tail], node_type: :block} = context,
        :expression,
        [
          {:symbol, "}"} = token | rest
        ]
      ) do
    context
    |> buffer_token(token)
    |> add_block_start_tag()
    |> add_processed_token(token)
    |> pop_delimiter_stack()
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> set_node_type(:text)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(
        %{delimiter_stack: [:expression | _tail], node_type: node_type} = context,
        :expression,
        [
          {:symbol, "}"} = token | rest
        ]
      )
      when node_type == :text or node_type == :public_comment do
    context
    |> buffer_token(token)
    |> add_expression_tag()
    |> pop_delimiter_stack()
    |> add_processed_token(token)
    |> reset_token_buffer()
    |> set_prev_status(:expression)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{delimiter_stack: [:curly_bracket | _tail]} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{delimiter_stack: [:elixir_interpolation | _tail]} = context, :expression, [
        {:symbol, "}"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_expression(token, rest)
  end

  def parse_tokens(context, :expression, [token | rest]) do
    parse_expression(context, token, rest)
  end

  # --- START TAG NAME ---

  def parse_tokens(context, :start_tag_name, [{:string, tag_name} = token | rest]) do
    context
    |> reset_attributes()
    |> set_tag_name(tag_name)
    |> maybe_enable_script_mode(tag_name)
    |> add_processed_token(token)
    |> set_prev_status(:start_tag_name)
    |> parse_tokens(:start_tag, rest)
  end

  # --- START TAG ---

  def parse_tokens(context, :start_tag, []) do
    details = """
    Reason:
    Unclosed start tag.

    Hint:
    Close the start tag with '>' character.
    """

    raise_error(details, context, :start_tag, nil, [])
  end

  def parse_tokens(context, :start_tag, [{:whitespace, _value} = token | rest]) do
    context
    |> add_processed_token(token)
    |> parse_tokens(:start_tag, rest)
  end

  def parse_tokens(context, :start_tag, [{:symbol, "="} = token | rest]) do
    details = """
    Reason:
    Missing attribute name.

    Hint:
    Specify the attribute name before the '=' character.
    """

    raise_error(details, context, :start_tag, token, rest)
  end

  def parse_tokens(context, :start_tag, [{:symbol, "/>"} = token | rest]) do
    parse_start_tag_end(context, token, rest, true)
  end

  def parse_tokens(context, :start_tag, [{:symbol, ">"} = token | rest]) do
    parse_start_tag_end(context, token, rest, false)
  end

  def parse_tokens(context, :start_tag, [{:string, _str} = token | rest]) do
    context
    |> reset_attribute_value()
    |> reset_token_buffer()
    |> set_prev_status(:start_tag)
    |> parse_attribute_name(token, rest)
  end

  def parse_tokens(context, :start_tag, [{:symbol, "$"} = token | rest]) do
    context
    |> reset_attribute_value()
    |> reset_token_buffer()
    |> set_prev_status(:start_tag)
    |> parse_attribute_name(token, rest)
  end

  # --- TEXT ---

  def parse_tokens(%{node_type: :public_comment} = context, :text, []) do
    details = """
    Reason:
    Unclosed public comment.

    Hint:
    Close the public comment with '-->' marker.
    """

    raise_error(details, context, :text, nil, [])
  end

  def parse_tokens(context, :text, []) do
    context
    |> maybe_add_text_tag()
    |> Map.fetch!(:processed_tags)
    |> Enum.reverse()
  end

  def parse_tokens(%{node_type: :attribute} = context, :text, [{:symbol, "\""} = token | rest]) do
    context
    |> add_attribute_value_part(:text)
    |> flush_attribute()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> parse_tokens(:start_tag, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: []} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> push_delimiter_stack(:double_quote)
    |> parse_text(token, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: [:double_quote | _tail]} = context, :text, [
        {:symbol, "\""} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_text(token, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: []} = context, :text, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> push_delimiter_stack(:single_quote)
    |> parse_text(token, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: [:single_quote | _tail]} = context, :text, [
        {:symbol, "'"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_text(token, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: []} = context, :text, [
        {:symbol, "`"} = token | rest
      ]) do
    context
    |> push_delimiter_stack(:backtick)
    |> parse_text(token, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: [:backtick | _tail]} = context, :text, [
        {:symbol, "`"} = token | rest
      ]) do
    context
    |> pop_delimiter_stack()
    |> parse_text(token, rest)
  end

  def parse_tokens(context, :text, [{:symbol, "\\{"} = token | rest]) do
    context
    |> buffer_token({:symbol, "{"})
    |> add_processed_token(token)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{node_type: :text, script?: false} = context, :text, [
        {:symbol, "<!--"} = token | rest
      ]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_public_comment_start_tag()
    |> add_processed_token(token)
    |> set_node_type(:public_comment)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{node_type: :public_comment} = context, :text, [
        {:symbol, "<!--"} | [{:symbol, ">"} | rest]
      ]) do
    parse_tokens(context, :text, [{:symbol, "<!"} | [{:symbol, "-->"} | rest]])
  end

  def parse_tokens(%{node_type: :public_comment} = context, :text, [
        {:symbol, "<!--"} = token | rest
      ]) do
    parse_text(context, token, rest)
  end

  def parse_tokens(%{node_type: :text, script?: false} = context, :text, [
        {:symbol, "<!"} = token_1 | rest_1
      ]) do
    case rest_1 do
      [{:string, str} = token_2 | rest_2] ->
        if String.downcase(str) == "doctype" do
          context
          |> maybe_add_text_tag()
          |> reset_token_buffer()
          |> add_processed_token(token_1)
          |> add_processed_token(token_2)
          |> parse_tokens(:doctype, rest_2)
        else
          raise_error(@unescaped_lt_char_details, context, :text, token_1, rest_1)
        end

      _fallback ->
        raise_error(@unescaped_lt_char_details, context, :text, token_1, rest_1)
    end
  end

  def parse_tokens(%{node_type: :public_comment} = context, :text, [
        {:symbol, "-->"} = token | rest
      ]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_public_comment_end_tag()
    |> add_processed_token(token)
    |> set_node_type(:text)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{%raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> enable_raw_mode()
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{raw?: true} = context, :text, [{:symbol, "{/raw}"} = token | rest]) do
    context
    |> add_processed_token(token)
    |> disable_raw_mode()
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{%else}"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> add_processed_tag({:block_start, "else"})
    |> reset_token_buffer()
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{%for"} = token | rest]) do
    parse_block_start(context, "for", token, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{/for}"} = token | rest]) do
    parse_block_end(context, "for", token, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{%if"} = token | rest]) do
    parse_block_start(context, "if", token, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{/if}"} = token | rest]) do
    parse_block_end(context, "if", token, rest)
  end

  def parse_tokens(%{raw?: false, node_type: :attribute} = context, :text, [
        {:symbol, "{"} = token | rest
      ]) do
    context
    |> add_attribute_value_part(:text)
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> push_delimiter_stack(:expression)
    |> parse_expression(token, rest)
  end

  def parse_tokens(%{raw?: false} = context, :text, [{:symbol, "{"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> set_prev_status(:text)
    |> push_delimiter_stack(:expression)
    |> parse_expression(token, rest)
  end

  def parse_tokens(context, :text, [{:symbol, "\\}"} = token | rest]) do
    context
    |> buffer_token({:symbol, "}"})
    |> add_processed_token(token)
    |> parse_tokens(:text, rest)
  end

  def parse_tokens(%{script?: true, delimiter_stack: [delimiter | _tail]} = context, :text, [
        {:symbol, "</"} = token | rest
      ])
      when delimiter in [:backtick, :double_quote, :single_quote] do
    parse_text(context, token, rest)
  end

  def parse_tokens(%{node_type: :text} = context, :text, [{:symbol, "</"} = token | rest]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> parse_tokens(:end_tag_name, rest)
  end

  def parse_tokens(%{node_type: :text, script?: false} = context, :text, [
        {:symbol, "<"} = token | [{:string, _value} | _tokens] = rest
      ]) do
    context
    |> maybe_add_text_tag()
    |> reset_token_buffer()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> set_node_type(:tag)
    |> parse_tokens(:start_tag_name, rest)
  end

  def parse_tokens(%{node_type: :text, script?: false} = context, :text, [
        {:symbol, "<"} = token | rest
      ]) do
    raise_error(@unescaped_lt_char_details, context, :text, token, rest)
  end

  def parse_tokens(%{node_type: :text, script?: false} = context, :text, [
        {:symbol, ">"} = token | rest
      ]) do
    details = """
    Reason:
    Unescaped '>' character inside text node.

    Hint:
    To escape use HTML entity: '&gt;'.
    """

    raise_error(details, context, :text, token, rest)
  end

  def parse_tokens(context, :text, [token | rest]) do
    parse_text(context, token, rest)
  end

  # These two cases shouldn't happen once we've got template syntax errors covered.

  def parse_tokens(context, type, [token | rest]) do
    raise_error(@default_error_details, context, type, token, rest)
  end

  def parse_tokens(context, type, []) do
    raise_error(@default_error_details, context, type, nil, [])
  end

  @doc """
  Prints debug info for intercepted parse/3 calls.
  """
  @spec debug({module, atom, list}, list | %{__struct__: FunctionClauseError}, integer) :: :ok
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
    part = {type, encode_tokens(context.token_buffer)}
    %{context | attribute_value: [part | context.attribute_value]}
  end

  defp add_block_start_tag(context) do
    expression = encode_tokens(context.token_buffer)
    new_tag = {:block_start, {context.block_name, expression}}
    add_processed_tag(context, new_tag)
  end

  defp add_block_end_tag(context, block_name) do
    new_tag = {:block_end, block_name}
    add_processed_tag(context, new_tag)
  end

  defp add_doctype_declaration(%{token_buffer: token_buffer} = context) do
    content =
      token_buffer
      |> encode_tokens()
      |> String.trim()

    new_tag = {:doctype, content}

    add_processed_tag(context, new_tag)
  end

  defp add_end_tag(context) do
    new_tag = {:end_tag, context.tag_name}
    add_processed_tag(context, new_tag)
  end

  defp add_expression_tag(%{token_buffer: token_buffer} = context) do
    new_tag = {:expression, encode_tokens(token_buffer)}
    add_processed_tag(context, new_tag)
  end

  defp add_processed_tag(%{processed_tags: processed_tags} = context, tag) do
    %{context | processed_tags: [tag | processed_tags]}
  end

  defp add_processed_token(%{processed_tokens: processed_tokens} = context, token) do
    %{context | processed_tokens: [token | processed_tokens]}
  end

  defp add_public_comment_end_tag(context) do
    add_processed_tag(context, :public_comment_end)
  end

  defp add_public_comment_start_tag(context) do
    add_processed_tag(context, :public_comment_start)
  end

  defp add_self_closing_tag(context) do
    attributes = Enum.reverse(context.attributes)
    new_tag = {:self_closing_tag, {context.tag_name, attributes}}
    add_processed_tag(context, new_tag)
  end

  defp add_start_tag(context) do
    attributes = Enum.reverse(context.attributes)
    new_tag = {:start_tag, {context.tag_name, attributes}}
    add_processed_tag(context, new_tag)
  end

  defp buffer_token(%{token_buffer: token_buffer} = context, token) do
    %{context | token_buffer: [token | token_buffer]}
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
    tokens
    |> Enum.reverse()
    |> join_tokens()
  end

  defp escape_non_printable_chars(str) do
    str
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp flush_attribute(context) do
    new_attr = {context.attribute_name, Enum.reverse(context.attribute_value)}

    %{
      context
      | attribute_name: nil,
        attribute_value: [],
        attributes: [new_attr | context.attributes]
    }
  end

  defp join_tokens(tokens) do
    Enum.map_join(tokens, "", fn {_type, value} -> value end)
  end

  defp maybe_add_text_tag(%{token_buffer: token_buffer} = context) do
    if Enum.any?(token_buffer) do
      text_tag = {:text, encode_tokens(token_buffer)}
      add_processed_tag(context, text_tag)
    else
      context
    end
  end

  defp maybe_disable_script_mode(context, "script") do
    disable_script_mode(context)
  end

  defp maybe_disable_script_mode(context, _tag_name), do: context

  defp maybe_enable_script_mode(context, "script") do
    enable_script_mode(context)
  end

  defp maybe_enable_script_mode(context, _tag_name), do: context

  defp parse_attribute_name(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse_tokens(:attribute_name, rest)
  end

  defp parse_block_end(context, block_name, token, rest) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> set_prev_status(:text)
    |> add_block_end_tag(block_name)
    |> set_prev_status(:block_end)
    |> reset_token_buffer()
    |> parse_tokens(:text, rest)
  end

  defp parse_block_start(context, block_name, token, rest) do
    context
    |> maybe_add_text_tag()
    |> add_processed_token(token)
    |> push_delimiter_stack(:expression)
    |> set_node_type(:block)
    |> set_block_name(block_name)
    |> reset_token_buffer()
    |> buffer_token({:symbol, "{"})
    |> set_prev_status(:block_start)
    |> parse_tokens(:expression, rest)
  end

  defp parse_expression(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse_tokens(:expression, rest)
  end

  defp parse_start_tag_end(context, token, rest, self_closing?) do
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
    |> parse_tokens(:text, rest)
  end

  defp parse_text(context, token, rest) do
    context
    |> buffer_token(token)
    |> add_processed_token(token)
    |> parse_tokens(:text, rest)
  end

  defp pop_delimiter_stack(%{delimiter_stack: [_head | tail]} = context) do
    %{context | delimiter_stack: tail}
  end

  defp push_delimiter_stack(context, delimiter) do
    %{context | delimiter_stack: [delimiter | context.delimiter_stack]}
  end

  defp raise_error(details, %{processed_tokens: processed_tokens} = context, status, token, rest) do
    encoded_tokens = encode_tokens(processed_tokens)
    encoded_tokens_len = String.length(encoded_tokens)

    prev_fragment =
      if encoded_tokens_len > 20 do
        String.slice(encoded_tokens, -20..-1)
      else
        encoded_tokens
      end

    escaped_prev_fragment = escape_non_printable_chars(prev_fragment)
    prev_fragment_len = String.length(escaped_prev_fragment)
    indent = String.duplicate(" ", prev_fragment_len)

    current_fragment =
      token
      |> List.wrap()
      |> encode_tokens()
      |> escape_non_printable_chars()

    next_fragment =
      rest
      |> join_tokens()
      |> String.slice(0, 20)
      |> escape_non_printable_chars()

    message = """


    #{details}
    #{escaped_prev_fragment}#{current_fragment}#{next_fragment}
    #{indent}^

    status = #{inspect(status)}

    token = #{inspect(token)}

    context = #{inspect(context)}
    """

    raise TemplateSyntaxError, message: message
  end

  defp reset_attribute_value(context) do
    %{context | attribute_value: []}
  end

  defp reset_attributes(context) do
    %{context | attributes: []}
  end

  defp reset_token_buffer(context) do
    %{context | token_buffer: []}
  end

  defp set_attribute_name(context) do
    %{context | attribute_name: encode_tokens(context.token_buffer)}
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
end
