defmodule Hologram.Template.Formatter do
  @moduledoc """
    A formatter for `~HOLO` sigil templates.

    Enable it by adding `Hologram.Template.Formatter` to the `plugins:` list
    in `.formatter.exs`
  """

  alias Hologram.Template.Parser
  require Logger

  @behaviour Mix.Tasks.Format

  defmodule State do
    defstruct indent_by: "  ",
              current_indent: "",
              last_tag_action: :none,
              embed: [],
              output: [],
              in_tree: []
  end

  @default_opts indent_by: "  "
  defp ensure_opts(inc) do
    Keyword.merge(@default_opts, inc)
  end

  @impl true
  def features(_opts) do
    # Will `.holo` be a thing eventually?
    [sigils: [:HOLO], extensions: []]
  end

  @impl true
  def format(contents, opts) do
    options = ensure_opts(opts)

    contents
    |> Parser.parse_markup()
    |> format_parse(%State{indent_by: options[:indent_by]})
  end

  # Keep the base case separate.
  # It's important and has the external function signature
  defp format_parse([], %State{output: out}) do
    out |> Enum.reverse() |> List.flatten()
  end

  # Special case trailing text
  defp format_parse([{:text, t}], state) do
    # This might just be whitespace to make the quoting correct
    # Regardless, it passes untouched.
    format_parse([], add_output(state, t, :raw))
  end

  defp format_parse([item | rest], state) do
    next_state =
      case item do
        # Looks like a tag, is decidedly not
        {:doctype, t} -> add_output(state, "<!DOCTYPE #{t}>", :raw)
        {:start_tag, t} -> stack_tag(state, t, :open)
        # This guard should be unneeded, but I've been surprised
        # by parses before
        {:end_tag, t} when is_binary(t) -> stack_tag(state, {t, []}, :close)
        {:block_start, b} -> enter_block(state, b)
        {:block_end, b} -> exit_block(state, b)
        :public_comment_start -> begin_comment(state)
        :public_comment_end -> end_comment(state)
        {:self_closing_tag, t} -> stack_tag(state, t, :self)
        {:text, t} -> add_literal(state, t, :text)
        {:expression, e} -> add_literal(state, e, :expression)
      end

    format_parse(rest, next_state)
  end

  # State adjusting functions follow

  defp adj_indent(state, :noop), do: state

  defp adj_indent(state, :inc) do
    %{
      state
      | current_indent: state.indent_by <> state.current_indent
    }
  end

  defp adj_indent(state, :dec) do
    %{state | current_indent: String.slice(state.current_indent, byte_size(state.indent_by)..100)}
  end

  # In the case of the first output, we'll continue to respect it they want a
  # whole body indent but elide the leading new line
  defp add_output(%State{output: []} = state, output, :indent) do
    %{state | output: [output, state.current_indent]}
  end

  defp add_output(%State{output: out} = state, output, :indent) do
    %{state | output: [output | [state.current_indent | ["\n" | out]]]}
  end

  defp add_output(state, output, :raw) do
    %{state | output: [output | state.output]}
  end

  defp add_literal(%State{embed: e, in_tree: it, last_tag_action: lta} = state, text, :text) do
    case String.match?(text, ~r/^\s*$/) do
      # We're a formatter we'll handle the whitespace
      true ->
        state

      false ->
        # When a `block` tag has just now opened and we are not otherwise embedded
        # we indent this text despite appearances otherwise
        outmode =
          case length(e) == 0 and lta == :open and is_block?(List.first(it)) do
            true -> :indent
            false -> :raw
          end

        state |> embed(:add) |> add_output(text, outmode)
    end
  end

  # We treat expressions as text essentially.
  defp add_literal(state, exp, :expression) do
    state |> embed(:add) |> add_output(exp, :raw)
  end

  defp add_literal(state, lit, atom), do: IO.inspect({state, lit, atom})

  defp last_tag_action(state, which), do: %{state | last_tag_action: which}

  defp begin_comment(state) do
    state
    |> add_output("<!--", :raw)
    |> push_tag({"<!--", []})
    |> embed(:add)
  end

  defp end_comment(state) do
    state
    |> add_output("-->", :raw)
    |> embed({"<!--", []}, :drop)
  end

  defp enter_block(state, {bt, be}) do
    state
    |> add_output("{%#{bt} #{block_exp(be)}}", :indent)
    |> adj_indent(:inc)
  end

  # Special case; we don't even ensure it's inside another block
  defp enter_block(state, "else") do
    state
    |> adj_indent(:dec)
    |> add_output("{%else}", :indent)
    |> adj_indent(:inc)
  end

  defp exit_block(state, bt) do
    state
    |> adj_indent(:dec)
    |> add_output("{/#{bt}}", :indent)
  end

  defp block_exp(str) do
    # This feels like it should be easier
    str
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.trim()
  end

  defp stack_tag(state, tag, :self) do
    # Despite its name, this won't actually add to the stack
    # It might be worth moving the atom parameter to the function name and
    # breaking these apart
    {mode, _} = indent_mode(state, tag, :self)

    state
    |> last_tag_action(:self)
    |> add_output(tag_string(tag, :self), mode)
  end

  defp stack_tag(state, tag, :open) do
    {mode, adj} = indent_mode(state, tag, :open)

    state
    |> last_tag_action(:open)
    |> add_output(tag_string(tag, :open), mode)
    |> push_tag(tag)
    |> adj_indent(adj)
  end

  defp stack_tag(state, {t, _} = tag_info, :close) do
    {mode, adj} = indent_mode(state, tag_info, :close)

    state
    |> pop_tag()
    |> last_tag_action(:close)
    |> adj_indent(adj)
    |> add_output(tag_string(tag_info, :close), mode)
    |> embed(t, :drop)
  end

  # We need to deal with the case of rootless text-like document fragments
  # We'll never close the "" and we'll stay embedded
  defp embed(%State{embed: e, in_tree: []} = state, :add), do: %{state | embed: ["" | e]}
  # Otherwise when the latest previous tag closes we're "free"
  # Note that this can have different level of depth as we go
  defp embed(%State{embed: e, last_tag_action: :open, in_tree: [{t, _} | _]} = state, :add),
    do: %{state | embed: [t | e]}

  # Nothing recently opened, so we're not deeper in
  defp embed(state, :add), do: state

  # If we're not noted as embedded, we can go on happy
  defp embed(%State{embed: []} = state, _, :drop), do: state
  # This closing tag matches as expected, we can drop it and continue
  defp embed(%State{embed: [tag | ged]} = state, tag, :drop), do: %{state | embed: ged}
  # This is mismatched so we warn and do nothing
  defp embed(%State{embed: e} = state, tag, :drop) do
    Logger.warning(
      "unexpected text closing tag. expected: '#{inspect(tag)}' saw: '#{inspect(e)}'"
    )

    state
  end

  @raw {:raw, :noop}

  # If either is raw then so is this
  defp indent_mode(state, tag, :self) do
    case indent_mode(state, tag, :open) do
      @raw -> @raw
      _ -> indent_mode(state, tag, :close)
    end
  end

  defp indent_mode(%State{in_tree: [pt | _]}, _tag, :close) do
    case is_block?(pt) do
      true -> {:indent, :dec}
      false -> @raw
    end
  end

  defp indent_mode(%State{embed: e, last_tag_action: lta}, tag, :open)
       when e == [] or lta == :close do
    case is_block?(tag) do
      true -> {:indent, :inc}
      false -> {:indent, :noop}
    end
  end

  defp indent_mode(_, _, _), do: @raw

  @block_tags MapSet.new([
                "div",
                "head",
                "body",
                "html",
                "main",
                "nav",
                "table",
                "tr",
                "tbody",
                "thead"
              ])

  defp is_block?({tn, _ta}), do: is_block?(tn)
  defp is_block?(tn) when is_binary(tn), do: MapSet.member?(@block_tags, tn)
  defp is_block?(nil), do: false
  defp is_block?(_), do: :error

  defp push_tag(state, tag) do
    %{state | in_tree: [tag | state.in_tree]}
  end

  defp pop_tag(%State{in_tree: [_ | tart]} = state), do: %{state | in_tree: tart}
  defp pop_tag(%State{in_tree: []} = state), do: state

  # Utility string functions follow
  defp tag_string({t, a}, :open), do: "<#{t}#{attrs_string(a)}>"
  defp tag_string({t, a}, :close), do: "</#{t}#{attrs_string(a)}>"
  # The space is a stylistic choice.  Should maybe be configurable.
  defp tag_string({t, a}, :self), do: "<#{t}#{attrs_string(a)} />"

  # This basically a reduce that I didn't want to inline
  defp attrs_string(attrs, acc \\ [])
  defp attrs_string([], []), do: ""
  defp attrs_string([], acc), do: " #{acc |> Enum.reverse() |> Enum.join(" ")}"
  defp attrs_string([attr | rest], acc), do: attrs_string(rest, [attr_string(attr) | acc])

  # For formatting purposes, expressions are unquoted text
  defp attr_string({k, [expression: v]}), do: "#{k}=#{v}"
  defp attr_string({k, [text: v]}), do: "#{k}=\"#{v}\""
  # Unary attribute parse result
  defp attr_string({k, []}), do: "#{k}"
end
