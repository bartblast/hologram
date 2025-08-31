defmodule Hologram.Template.Formatter do
  @moduledoc """
    A formatter for `~HOLO` sigil templates.

    Enable it by adding `Hologram.Template.Formatter` to the `plugins:` list
    in `.formatter.exs`
  """

  @behaviour Mix.Tasks.Format

  @per_indent 2

  defmodule State do
    defstruct current_indent: 0,
              pending_indent: "",
              output: []
  end

  @impl true
  def features(_opts) do
    # Will `.holo` be a thing eventually?
    [sigils: [:HOLO], extensions: []]
  end

  @impl true
  def format(contents, _opts) do
    contents
    |> Hologram.Template.Parser.parse_markup()
    |> format_parse(%State{})
  end

  # Keep the base case separate.
  # It's important and has the external function signature
  defp format_parse([], %State{pending_indent: pi, output: out}) do
    [pi | out] |> Enum.reverse() |> List.flatten()
  end

  defp format_parse([item | rest], state) do
    next_state =
      case item do
        # Looks like a tag, is decidedly not
        {:doctype, t} -> add_output(state, "<!DOCTYPE #{t}>")
        {:start_tag, t} -> insert_tag(state, t, :open)
        # This guard should be unneeded, but I've been surprised
        # by parses before
        {:end_tag, t} when is_binary(t) -> insert_tag(state, {t, []}, :close)
        {:block_start, b} -> enter_block(state, b)
        {:block_end, b} -> exit_block(state, b)
        :public_comment_start -> begin_comment(state)
        :public_comment_end -> end_comment(state)
        {:self_closing_tag, t} -> insert_tag(state, t, :self)
        {:text, t} -> add_trimmed_text(state, t)
        {:expression, e} -> add_output(state, e)
      end

    format_parse(rest, next_state)
  end

  # State adjusting functions follow
  defp adj_indent(state, how) do
    next_indent =
      case how do
        :inc -> min(state.current_indent + @per_indent, 40)
        :dec -> max(0, state.current_indent - @per_indent)
      end

    %{state | current_indent: next_indent}
  end

  # Do not start with a newline
  defp indent_next(%State{output: []} = state), do: state
  # Do not double indent
  defp indent_next(state) do
    %{
      state
      | pending_indent: "\n" <> String.duplicate(" ", state.current_indent)
    }
  end

  defp add_output(%State{pending_indent: pi, output: curr} = state, to_add),
    do: %{state | pending_indent: "", output: [to_add | [pi | curr]]}

  defp add_trimmed_text(state, text) do
    # We're a formatter we'll handle the whitespace
    case near_trim(text) do
      :skip -> state
      trimmed -> state |> add_output(trimmed)
    end
  end

  defp begin_comment(state) do
    state |> add_output("<!--")
  end

  defp end_comment(state) do
    state |> add_output("-->")
  end

  defp enter_block(state, {bt, be}) do
    state |> add_output("{%#{bt} #{block_exp(be)}}")
  end

  defp enter_block(state, "else") do
    state |> add_output("{%else}")
  end

  defp exit_block(state, bt) do
    state |> add_output("{/#{bt}}")
  end

  defp block_exp(str) do
    # This feels like it should be easier
    str
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.trim()
  end

  defp insert_tag(state, tag, how) do
    case {is_block?(tag), how} do
      {true, :open} ->
        state
        |> indent_next()
        |> add_output(tag_string(tag, how))
        |> adj_indent(:inc)
        |> indent_next()

      {true, :close} ->
        state
        |> adj_indent(:dec)
        |> indent_next()
        |> add_output(tag_string(tag, how))
        |> indent_next()

      _ ->
        state |> add_output(tag_string(tag, how))
    end
  end

  @block_tags MapSet.new([
                "article",
                "aside",
                "body",
                "blockquote",
                "canvas",
                "dd",
                "div",
                "dl",
                "dt",
                "fieldset",
                "figure",
                "footer",
                "form",
                "head",
                "header",
                "html",
                "hr",
                "main",
                "nav",
                "noscript",
                "ol",
                "p",
                "pre",
                "section",
                "table",
                "tbody",
                "tfoot",
                "thead",
                "tr",
                "ul"
              ])

  defp is_block?({tn, _ta}), do: is_block?(tn)
  defp is_block?(tn) when is_binary(tn), do: MapSet.member?(@block_tags, tn)
  defp is_block?(_), do: false

  # We will only concern ourselves with ASCII whitespace
  # If they've brought us some other kind, we'll assume that
  # it has significance to them
  @whitespace [9, 10, 11, 12, 13]
  @actual_space 32

  # We want to collapse leading and trailing whitespace to
  # a single ASCII space.  For matching convenience we treat an empty
  # string as a single space.
  # This is wholly unsuitable outside of this module.
  def near_trim(<<>>), do: " "

  def near_trim(binary) do
    potential =
      binary
      |> to_charlist
      |> close_shave()
      |> Enum.reverse()
      |> close_shave()
      |> Enum.reverse()
      |> to_string

    case potential do
      " " -> :skip
      "" -> :skip
      _ -> potential
    end
  end

  defp close_shave(chars, give_space \\ false)
  defp close_shave([h | t], _) when h in @whitespace, do: close_shave(t, false)
  # If we remove an actual space, we'll put exactly one back
  # Other whitespace is bad for our formatting purposes
  defp close_shave([@actual_space | t], _), do: close_shave(t, true)
  defp close_shave(despaced, true), do: [32 | despaced]
  defp close_shave(despaced, false), do: despaced

  # Utility string functions follow
  defp tag_string({t, a}, :open), do: "<#{t}#{attrs_string(a)}>"
  defp tag_string({t, a}, :close), do: "</#{t}#{attrs_string(a)}>"
  # The space is a stylistic choice.  Should maybe be configurable.
  defp tag_string({t, a}, :self), do: "<#{t}#{attrs_string(a)} />"

  # This would have sucked as an originally intended reduce
  defp attrs_string(attrs, acc \\ [])
  defp attrs_string([], []), do: ""
  defp attrs_string([], acc), do: " #{acc |> Enum.reverse() |> Enum.join(" ")}"
  defp attrs_string([attr | rest], acc), do: attrs_string(rest, [single_attr(attr) | acc])

  # Special case unary to leave out the `=`
  defp single_attr({k, []}), do: k
  defp single_attr({k, abits}), do: "#{k}=#{gather_abits(abits)}"

  defp gather_abits([]), do: ""

  defp gather_abits([{:text, t} | rest]) do
    # Skip "blank" and "all whitespace" text
    # We cannot just trim, because the whitespace is significant inside
    # these quotes.  We also don't want to just add it.
    case near_trim(t) do
      :skip -> gather_abits(rest)
      tt -> "\"#{tt}#{gather_abits(rest)}\""
    end
  end

  # Pass-thru unmangled and unquoted
  defp gather_abits([{:expression, e} | rest]), do: "{#{block_exp(e)}}#{gather_abits(rest)}"
end
