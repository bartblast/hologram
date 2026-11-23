defmodule Hologram.Migration.Value.RowFill do
  @moduledoc false

  # Runs a backfill written in Elixir, which has no SQL form: reads the rows in pages by id, calls
  # the migration's function on each, and writes each page back in one statement. The rows are
  # locked as they're read, since the function works from a copy of them.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Validator
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.FillCheck
  alias Hologram.Migration.Value.Resolver

  @page_size 1000

  # How many of a page's rows a refusal names.
  @named_rows 5

  @doc """
  Fills the given `fill_column` op's column by calling its function on each row, or on each row
  holding NULL when it fills only those, whose ids it keeps for FillCheck. A row the function gives
  nil is left NULL. Returns how many rows it wrote.

  Raises naming the row on a raise in the function, on a result that isn't of the column's type or
  that its unique index can't carry, and on a key it repeats or an id no row of the target holds.
  """
  @spec run!(%{atom => any}, pos_integer) :: non_neg_integer
  def run!(op, page_size \\ @page_size) do
    walk_pages(op, read_statement(op), write_statement(op), page_size, nil, 0)
  end

  defp call!(op, id, args) do
    {module, function} = op.function

    apply(module, function, args)
  catch
    kind, reason ->
      refuse!(
        op,
        "raised on row #{id}: #{Exception.format_banner(kind, reason, __STACKTRACE__)}"
      )
  end

  defp check_bytes!(value, %{max_bytes: max_bytes, type: :string} = op, id)
       when is_integer(max_bytes) and byte_size(value) > max_bytes do
    refuse!(
      op,
      "returned a value for row #{id} that " <>
        Validator.requirement_description({:max_bytes, max_bytes})
    )
  end

  defp check_bytes!(_value, _op, _id), do: :ok

  defp check_type!(value, op, id) do
    if not fits?(value, op) do
      refuse!(
        op,
        "returned #{inspect(value)} for row #{id}, which isn't #{spell_type(op)} - change the fn"
      )
    end
  end

  defp fill_row([id | row_values], op) do
    args =
      op.arg_columns
      |> Enum.zip(row_values)
      |> Enum.map(fn {{_column, type}, value} -> Codec.decode(value, type) end)

    case call!(op, id, args) do
      nil ->
        nil

      result ->
        value = Value.normalize_constant(result, op.column_type)

        check_type!(value, op, id)
        check_bytes!(value, op, id)

        {id, value, Codec.encode(value, op.column_type)}
    end
  end

  defp fits?(value, %{column_type: :enum, rules: rules}) do
    is_atom(value) and value in Keyword.fetch!(rules, :values)
  end

  defp fits?(value, %{column_type: type}) do
    Resolver.fits_type?(value, type) and Resolver.storable?(value)
  end

  # The columns and the value of the key PostgreSQL's error detail names, which keeps this part
  # untranslated. Each is nil in the few translations leaving the key out.
  defp key_parts(detail) do
    case Regex.run(~r/\((.*?)\)=\((.*)\)/s, detail || "") do
      [_detail, columns, key] -> {columns, key}
      nil -> {nil, nil}
    end
  end

  # The rows holding the key when its text is the value's, which a key over several columns or a
  # value the database spells its own way isn't.
  defp key_rows(_filled, nil), do: []

  defp key_rows(filled, key) do
    for {id, value, _encoded} <- filled, key_text(value) == key, do: id
  end

  defp key_text(%Date{} = value), do: Date.to_iso8601(value)

  defp key_text(value) when is_binary(value) or is_atom(value) or is_number(value) do
    to_string(value)
  end

  defp key_text(_value), do: nil

  defp quoted(name), do: Mapper.quote_identifier(name)

  # The id comes back under another name so that ORDER BY reads the uuid column, as in FillCheck.
  # sobelow_skip ["SQL.Query"]
  defp read_statement(op) do
    column = Mapper.quote_identifier(op.column)

    selected =
      Enum.map_join(op.arg_columns, ", ", fn {name, _type} -> ~s("$r".#{quoted(name)}) end)

    only_nulls = if op.nulls_only, do: ~s| AND "$r".#{column} IS NULL|, else: ""

    ~s|SELECT "$r"."id"::text AS "$after_id", #{selected} FROM #{table(op)} AS "$r" | <>
      ~s|WHERE ($1::text IS NULL OR "$r"."id" > $1::text::uuid)#{only_nulls} | <>
      ~s|ORDER BY "$r"."id" LIMIT $2 FOR UPDATE|
  end

  @spec refuse!(%{atom => any}, String.t()) :: no_return
  defp refuse!(op, message) do
    raise ~s|the backfill of column "#{op.column}" on table "#{op.table}" (line #{op.line}) | <>
            message
  end

  defp spell_type(%{column_type: :enum, rules: rules}) do
    "one of #{inspect(Keyword.fetch!(rules, :values))}"
  end

  defp spell_type(%{column_type: type, fill_target: nil}), do: "a value of type #{inspect(type)}"

  defp spell_type(%{fill_target: target}), do: "the id of a #{inspect(target)}"

  defp table(op), do: ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(op.table)})

  defp walk_pages(op, read, write, page_size, after_id, count) do
    {:ok, %{rows: rows}} = Connection.query(read, [after_id, page_size])

    filled =
      rows
      |> Enum.map(&fill_row(&1, op))
      |> Enum.reject(&is_nil/1)

    write_page(op, write, filled)

    new_count = count + length(filled)

    if length(rows) == page_size do
      [last_id | _values] = List.last(rows)

      walk_pages(op, read, write, page_size, last_id, new_count)
    else
      new_count
    end
  end

  # A key over several columns can't be told from one row's value, so it names the page.
  defp where_repeated(filled, rows) do
    case rows do
      [] ->
        {first_id, _value, _encoded} = hd(filled)
        {last_id, _value, _encoded} = List.last(filled)

        "in the page of rows from #{first_id} to #{last_id}"

      ids ->
        named =
          ids
          |> Enum.take(@named_rows)
          |> Enum.join(", ")

        "on rows including #{named}"
    end
  end

  defp write_page(_op, _write, []), do: :ok

  defp write_page(op, write, filled) do
    ids = Enum.map(filled, &elem(&1, 0))
    values = Enum.map(filled, &elem(&1, 2))

    case Connection.query(write, [ids, values]) do
      {:ok, _result} ->
        if op.nulls_only, do: FillCheck.keep_filled_ids!(ids)

      {:error, %{postgres: %{code: :unique_violation} = error}} ->
        {columns, key} = key_parts(error[:detail])
        rows = if columns == op.column, do: key_rows(filled, key), else: []

        refuse!(
          op,
          "repeats the key #{inspect(key)} of a unique index, #{where_repeated(filled, rows)} - " <>
            "change the fn or the rows"
        )

      {:error, %{postgres: %{code: :foreign_key_violation} = error}} ->
        {_columns, key} = key_parts(error[:detail])
        {first_id, _value, _encoded} = hd(filled)

        row =
          filled
          |> key_rows(key)
          |> List.first(first_id)

        refuse!(
          op,
          "writes #{key || "an id"} on row #{row}, which no #{inspect(op.fill_target)} holds - " <>
            "change the fn or add that row"
        )

      {:error, error} ->
        raise error
    end
  end

  # An enum goes through text, since the driver can't name a type made in this transaction.
  # sobelow_skip ["SQL.Query"]
  defp write_statement(%{column_type: :enum} = op) do
    type = ~s("#{Mapper.data_schema()}".#{quoted(op.column_sql_type)})

    write_statement(op, "text", ~s("$v".value::#{type}))
  end

  defp write_statement(op), do: write_statement(op, op.column_sql_type, ~s("$v".value))

  # sobelow_skip ["SQL.Query"]
  defp write_statement(op, array_type, value) do
    ~s|UPDATE #{table(op)} AS "$t" SET #{quoted(op.column)} = #{value} | <>
      ~s|FROM unnest($1::text[], $2::#{array_type}[]) AS "$v"(id, value) | <>
      ~s|WHERE "$t"."id" = "$v".id::uuid|
  end
end
