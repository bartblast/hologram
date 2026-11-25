defmodule Hologram.Query.Words do
  @moduledoc false

  # What each query word computes, in Elixir, over values already read. A word's meaning lives
  # here once, so everything that runs one agrees with the database. Its SQL is in
  # Hologram.DB.WordSQL.

  alias Hologram.Query.Ordering

  # TODO(#1854): once the words work in queries, remove this list and the hint built from it. An
  # entity's own function of a word's name keeps winning in a derived body (#1853), so the words
  # can't simply join the stages a derived body imports.
  @backfill_only_words [:at, :coalesce, :most_common, :split]

  @backfill_only_hint_start " - if you meant the query word "

  @doc """
  Returns the part of the given split at the given position, counting from 0, as `Enum.at/2` does:
  nil past the end, and nil for a nil list.
  """
  @spec at(list(String.t()) | nil, non_neg_integer) :: String.t() | nil
  def at(nil, _position), do: nil

  def at(parts, position), do: Enum.at(parts, position)

  @doc """
  Returns the given compile error with the hint for the given query expression added to its
  message, unless the message carries one already.
  """
  @spec add_backfill_only_hint(Exception.t(), Macro.t()) :: Exception.t()
  def add_backfill_only_hint(error, ast) do
    if String.contains?(error.message, @backfill_only_hint_start) do
      error
    else
      %{error | message: error.message <> backfill_only_hint(ast)}
    end
  end

  @doc """
  Returns what to add to a refusal of the given query expression when it calls something named
  like a word that works only in a migration's `backfill:` for now, or an empty string when it
  doesn't. A pinned expression and a module attribute are the surrounding code's, so their calls
  aren't words, and neither is what a quote holds as data.
  """
  @spec backfill_only_hint(Macro.t()) :: String.t()
  def backfill_only_hint(ast) do
    {_ast, word} =
      Macro.prewalk(ast, nil, fn
        {:^, _meta, _args}, word ->
          {nil, word}

        {:@, _meta, _args}, word ->
          {nil, word}

        {:quote, _meta, args}, word when is_list(args) ->
          {quote_code(args), word}

        {:|>, _meta, [left, {:quote, _quote_meta, args}]}, word when is_list(args) ->
          {quote_code([left | args]), word}

        {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Kernel]}, :|>]}, _meta,
         [left, {:quote, _quote_meta, args}]},
        word
        when is_list(args) ->
          {quote_code([left | args]), word}

        {name, _meta, args} = node, nil when name in @backfill_only_words and is_list(args) ->
          {node, name}

        node, word ->
          {node, word}
      end)

    if word do
      "#{@backfill_only_hint_start}#{word}, it works only in a migration's backfill: for now"
    else
      ""
    end
  end

  @doc """
  Returns the first of the given values that isn't nil, or nil when all are. A false is a value.
  Reads no value past the one it returns, so a stream computes only those.
  """
  @spec coalesce(Enumerable.t()) :: any
  def coalesce(values), do: Enum.find(values, &(not is_nil(&1)))

  @doc """
  Returns the given strings joined, or nil when any of them is nil.
  """
  @spec concat(list(String.t() | nil)) :: String.t() | nil
  def concat(values) do
    if Enum.any?(values, &is_nil/1), do: nil, else: Enum.join(values)
  end

  @doc """
  Returns how many rows the given set holds.
  """
  @spec count(list) :: non_neg_integer
  def count(rows), do: length(rows)

  @doc """
  Returns the value that appears most often among the given ones, skipping nil, or nil when none
  is left. A tie goes to the smallest value. Values group and order as `Ordering.compare/3` compares
  them, which is how the database's `GROUP BY` and `ORDER BY` treat them, an enum by the given
  ranks.
  """
  @spec most_common(list(any), %{atom => non_neg_integer} | nil) :: any
  def most_common(values, ranks \\ nil) do
    non_nil = Enum.reject(values, &is_nil/1)

    if non_nil == [] do
      nil
    else
      # Sorted ascending, so the first of the largest groups holds the smallest value.
      non_nil
      |> Enum.sort(&(Ordering.compare(&1, &2, ranks) != :gt))
      |> Enum.chunk_while([], &chunk_equal(&1, &2, ranks), &finish_chunk/1)
      |> Enum.max_by(&length/1)
      |> List.last()
    end
  end

  @doc """
  Returns the given text split by the given separator, as `String.split/2` does, or nil for nil.
  """
  @spec split(String.t() | nil, String.t()) :: list(String.t()) | nil
  def split(nil, _separator), do: nil

  def split(text, separator), do: String.split(text, separator)

  defp chunk_equal(value, [], _ranks), do: {:cont, [value]}

  defp chunk_equal(value, [head | _rest] = chunk, ranks) do
    if Ordering.compare(value, head, ranks) == :eq do
      {:cont, [value | chunk]}
    else
      {:cont, chunk, [value]}
    end
  end

  defp finish_chunk(chunk), do: {:cont, chunk, []}

  # A quote runs its options and what it unquotes, and holds the rest of its body as data. With
  # separate options, Elixir ignores any beside the do. An unquote it may run counts, so a word in
  # one isn't missed.
  defp quote_code(args) do
    {options, body} =
      case args do
        [options, block] -> {options, if(Keyword.keyword?(block), do: block[:do])}
        [single] -> if Keyword.keyword?(single), do: pop_do(single), else: {single, nil}
        _other -> {[], nil}
      end

    options_code = if Keyword.keyword?(options), do: Keyword.values(options), else: [options]

    if unquotes?(options), do: [unquoted(body) | options_code], else: options_code
  end

  defp pop_do(options) do
    {body, rest} = Keyword.pop(options, :do)

    {rest, body}
  end

  defp unquotes?(options) do
    if Keyword.keyword?(options) do
      Keyword.get(options, :unquote, not Keyword.has_key?(options, :bind_quoted)) != false
    else
      true
    end
  end

  # A nested quote keeps its body's unquotes for itself, but the unquotes in its separate options
  # are the enclosing quote's. A node put in place of another is walked below its root only, so the
  # options and a receiver go in a list, which an unquote at their root doesn't escape.
  defp unquoted(body) do
    {_body, code} =
      Macro.prewalk(body, [], fn
        {:quote, _meta, [options, _block]}, code ->
          {[options], code}

        {:quote, _meta, args}, code when is_list(args) ->
          {nil, code}

        {form, _meta, [expr]}, code when form in [:unquote, :unquote_splicing] ->
          {nil, [expr | code]}

        {{:., _dot_meta, [receiver, :unquote]}, _meta, [expr]}, code ->
          {[receiver], [expr | code]}

        node, code ->
          {node, code}
      end)

    Enum.reverse(code)
  end
end
