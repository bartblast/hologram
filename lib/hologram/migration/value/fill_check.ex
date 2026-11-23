defmodule Hologram.Migration.Value.FillCheck do
  @moduledoc false

  # Checks the values a computed fill wrote against the rules its member declares. Done in Elixir,
  # over the rows, because a format is a Regex and a length counts code points as the validator
  # does, and a value the validator refuses in a write mustn't arrive through a migration.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Validator
  alias Hologram.Migration.Value.Check

  @page_size 1000

  @rule_keys [:format, :in, :length, :max, :max_length, :min, :min_length]

  @doc """
  Validates the values the given `fill_column` op left in its column, in pages of the given size,
  and returns :ok. A member declaring no rule and no byte bound isn't read back.

  Raises naming each broken rule and how many rows break it.
  """
  @spec check!(%{atom => any}, pos_integer) :: :ok
  def check!(op, page_size \\ @page_size) do
    rules = Keyword.take(op.rules, @rule_keys)
    bounded_op = %{op | max_bytes: string_bound(op)}

    if rules != [] or bounded_op.max_bytes do
      opts = Check.runnable_opts(rules)
      broken = walk_pages(bounded_op, opts, statement(op), page_size, nil, %{})

      if broken != %{}, do: raise_broken!(op, broken)
    end

    :ok
  end

  defp byte_reasons(value, max_bytes)
       when is_binary(value) and is_integer(max_bytes) and byte_size(value) > max_bytes do
    [{:max_bytes, max_bytes}]
  end

  defp byte_reasons(_value, _max_bytes), do: []

  defp count_row(row_value, op, opts, broken) do
    value = Codec.decode(row_value, op.type)

    rule_reasons =
      for {_name, reason} <- Validator.value_errors(op.member, value, op.type, opts),
          do: reason

    Enum.reduce(rule_reasons ++ byte_reasons(value, op.max_bytes), broken, fn reason, counts ->
      Map.update(counts, reason, 1, &(&1 + 1))
    end)
  end

  defp pluralize_rows(1), do: "1 row"

  defp pluralize_rows(count), do: "#{count} rows"

  @spec raise_broken!(%{atom => any}, %{any => pos_integer}) :: no_return
  defp raise_broken!(op, broken) do
    rules =
      broken
      |> Enum.map(fn {reason, count} ->
        "#{Validator.requirement_description(reason)} (#{pluralize_rows(count)})"
      end)
      |> Enum.sort()
      |> Enum.join(", ")

    raise ~s(the backfill of column "#{op.column}" on table "#{op.table}" writes values ) <>
            "breaking the attribute's declared rules: #{rules} - change the expression or " <>
            "the rule"
  end

  # The id comes back under another name so that ORDER BY reads the uuid column, through its
  # index and in the order the cursor compares, rather than sorting the text.
  # sobelow_skip ["SQL.Query"]
  defp statement(op) do
    table = ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(op.table)})
    column = Mapper.quote_identifier(op.column)

    ~s|SELECT "id"::text AS "$after_id", #{column} FROM #{table} | <>
      ~s|WHERE #{column} IS NOT NULL AND ($1::text IS NULL OR "id" > $1::text::uuid) | <>
      ~s|ORDER BY "id" LIMIT $2|
  end

  # A later op can turn the member into a unique string, which bounds it at the file's end. Until
  # then it holds another type, whose text always fits the index.
  defp string_bound(%{max_bytes: max_bytes, type: :string}), do: max_bytes

  defp string_bound(_op), do: nil

  defp walk_pages(op, opts, statement, page_size, after_id, broken) do
    {:ok, %{rows: rows}} = Connection.query(statement, [after_id, page_size])

    counted =
      Enum.reduce(rows, broken, fn [_id, value], counts ->
        count_row(value, op, opts, counts)
      end)

    if length(rows) == page_size do
      [last_id, _value] = List.last(rows)

      walk_pages(op, opts, statement, page_size, last_id, counted)
    else
      counted
    end
  end
end
