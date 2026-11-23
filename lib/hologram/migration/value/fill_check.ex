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

  # The rows a fill of NULLs writes, kept apart since once it has run nothing else tells them from
  # the rows that already held a value.
  @filled_ids ~s("$fill_ids")

  @doc """
  Validates that no row holding NULL in the given `fill_column` op's column would take a value over
  the byte bound of its unique indexes, and returns :ok. Asked before the fill, since the index
  would fail in PostgreSQL before any value could be read back.

  Raises naming the bound and how many rows break it.
  """
  @spec check_bytes!(%{atom => any}) :: :ok
  def check_bytes!(%{max_bytes: max_bytes, type: :string} = op) when is_integer(max_bytes) do
    {fragment, params} = op.sql
    column = Mapper.quote_identifier(op.column)

    statement =
      ~s|SELECT COUNT(*) FROM #{table(op)} AS "$r0" WHERE "$r0".#{column} IS NULL | <>
        ~s|AND octet_length(#{fragment}) > $#{length(params) + 1}|

    {:ok, %{rows: [[count]]}} = Connection.query(statement, Enum.concat(params, [max_bytes]))

    if count > 0, do: raise_broken!(op, %{{:max_bytes, max_bytes} => count})

    :ok
  end

  def check_bytes!(_op), do: :ok

  @doc """
  Validates the values the given `fill_column` op left in its column, in pages of the given size,
  and returns :ok. A fill of NULLs reads only the rows fill_nulls!/1 kept. The options are
  `:page_size` and `:on_page`, a function each page's rows go to as [id, value] lists. With no
  function, a member declaring no rule and no byte bound isn't read back.

  Raises naming each broken rule and how many rows break it.
  """
  @spec check!(%{atom => any}, keyword) :: :ok
  def check!(op, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, @page_size)
    on_page = Keyword.get(opts, :on_page)
    rules = Keyword.take(op.rules, @rule_keys)
    bounded_op = %{op | max_bytes: string_bound(op)}

    if rules != [] or not is_nil(bounded_op.max_bytes) or not is_nil(on_page) do
      runnable = Check.runnable_opts(rules)
      broken = walk_pages(bounded_op, runnable, statement(op), page_size, nil, %{}, on_page)

      if broken != %{}, do: raise_broken!(op, broken)
    end

    :ok
  end

  @doc """
  Drops the ids fill_nulls!/1 kept, so another fill of the same file can keep its own.
  """
  @spec drop_filled_ids!() :: :ok
  def drop_filled_ids! do
    {:ok, _result} = Connection.query(~s|DROP TABLE #{@filled_ids}|)

    :ok
  end

  @doc """
  Fills the rows holding NULL in the given `fill_column` op's column with its expression, keeping
  their ids until drop_filled_ids!/0, for the current transaction at most. One statement does both,
  so a row committed while it starts can't be filled without being kept. It isn't paged, since a
  term reading the filled column through a self-reference would see earlier pages.

  Raises naming the grant when the role may not create temporary tables.
  """
  @spec fill_nulls!(%{atom => any}) :: :ok
  # sobelow_skip ["SQL.Query"]
  def fill_nulls!(op) do
    {fragment, params} = op.sql
    column = Mapper.quote_identifier(op.column)

    create_filled_ids!()

    statement =
      ~s|WITH "$filled" AS (UPDATE #{table(op)} AS "$r0" SET #{column} = #{fragment} | <>
        ~s|WHERE "$r0".#{column} IS NULL RETURNING "$r0"."id") | <>
        ~s|INSERT INTO #{@filled_ids} SELECT "id" FROM "$filled"|

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  defp byte_reasons(value, max_bytes)
       when is_binary(value) and is_integer(max_bytes) and byte_size(value) > max_bytes do
    [{:max_bytes, max_bytes}]
  end

  defp byte_reasons(_value, _max_bytes), do: []

  defp count_row(_row_value, %{max_bytes: nil}, [], broken), do: broken

  defp count_row(row_value, op, opts, broken) do
    value = Codec.decode(row_value, op.type)

    rule_reasons =
      for {_name, reason} <- Validator.value_errors(op.member, value, op.type, opts),
          do: reason

    Enum.reduce(rule_reasons ++ byte_reasons(value, op.max_bytes), broken, fn reason, counts ->
      Map.update(counts, reason, 1, &(&1 + 1))
    end)
  end

  defp create_filled_ids! do
    statement = ~s|CREATE TEMP TABLE #{@filled_ids} (id uuid PRIMARY KEY) ON COMMIT DROP|

    case Connection.query(statement) do
      {:ok, _result} ->
        :ok

      {:error, %{postgres: %{code: :insufficient_privilege}}} ->
        raise "a backfill filling the rows holding nil needs a temporary table, which this " <>
                "database role may not create - run GRANT TEMPORARY ON DATABASE <database> TO " <>
                "<role>"
    end
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
  defp statement(%{nulls_only: true} = op) do
    column = Mapper.quote_identifier(op.column)

    ~s|SELECT "$f"."id"::text AS "$after_id", "$t".#{column} | <>
      ~s|FROM #{@filled_ids} AS "$f" JOIN #{table(op)} AS "$t" ON "$t"."id" = "$f"."id" | <>
      ~s|WHERE "$t".#{column} IS NOT NULL AND ($1::text IS NULL OR "$f"."id" > $1::text::uuid) | <>
      ~s|ORDER BY "$f"."id" LIMIT $2|
  end

  # sobelow_skip ["SQL.Query"]
  defp statement(op) do
    column = Mapper.quote_identifier(op.column)

    ~s|SELECT "id"::text AS "$after_id", #{column} FROM #{table(op)} | <>
      ~s|WHERE #{column} IS NOT NULL AND ($1::text IS NULL OR "id" > $1::text::uuid) | <>
      ~s|ORDER BY "id" LIMIT $2|
  end

  # A later op can turn the member into a unique string, which bounds it at the file's end. Until
  # then it holds another type, whose text always fits the index.
  defp string_bound(%{max_bytes: max_bytes, type: :string}), do: max_bytes

  defp string_bound(_op), do: nil

  defp table(op), do: ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(op.table)})

  defp walk_pages(op, opts, statement, page_size, after_id, broken, on_page) do
    {:ok, %{rows: rows}} = Connection.query(statement, [after_id, page_size])

    if on_page, do: on_page.(rows)

    counted =
      Enum.reduce(rows, broken, fn [_id, value], counts ->
        count_row(value, op, opts, counts)
      end)

    if length(rows) == page_size do
      [last_id, _value] = List.last(rows)

      walk_pages(op, opts, statement, page_size, last_id, counted, on_page)
    else
      counted
    end
  end
end
