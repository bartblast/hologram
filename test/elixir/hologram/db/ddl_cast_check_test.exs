defmodule Hologram.DB.DDLCastCheckTest do
  # The data-dependent cast checks, run against real rows in a real database - one table
  # per conversion, one row per value, every edge the pair has.
  #
  # Two assertions per value, and the pairing is the point. The check statement's verdict
  # is the SPEC - what Hologram promises to refuse. The cast's own verdict is PostgreSQL's,
  # and every value the check passes must convert, or the applier's promise that PostgreSQL
  # never arbitrates is false. Asserting only the first would let the spec drift away from
  # the database it is a model of, which is how an out-of-range value came to pass the
  # check while failing the cast.
  #
  # The scratch tier, not the sandbox: a failing cast is its own statement here, where
  # under the sandbox it would poison the one transaction the whole test runs in.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.DB.DDL, only: [cast_check_statement: 4]

  alias Hologram.DB.Connection

  # Long enough to pass the length limit the float8 check guards its range comparison with,
  # and long enough that numeric refuses it outright - the two are checked together because
  # a guard that let this reach the comparison would raise instead of answering.
  defp long_digits(count), do: String.duplicate("9", count)

  # The check's verdict on one value: does the statement count this row?
  defp refused?(table, column, from_type, to_type) do
    statement = cast_check_statement(table, column, from_type, to_type)

    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count == 1
  end

  # PostgreSQL's own verdict on the same value, through the cast the applier would run.
  defp converts?(table, column, to_type) do
    statement = ~s{SELECT "#{column}"::#{to_type} FROM #{qualified(table)}}

    match?({:ok, _result}, Connection.query(statement))
  end

  # The check statements name the data schema, so the rows have to live there.
  defp qualified(table), do: ~s{"hologram_data"."#{table}"}

  defp seed_row(table, column, source_type, value) do
    {:ok, _result} = Connection.query(~s{CREATE SCHEMA IF NOT EXISTS "hologram_data"})
    {:ok, _result} = Connection.query(~s{DROP TABLE IF EXISTS #{qualified(table)}})

    {:ok, _result} =
      Connection.query(~s{CREATE TABLE #{qualified(table)} ("#{column}" #{source_type})})

    {:ok, _result} =
      Connection.query(~s{INSERT INTO #{qualified(table)} ("#{column}") VALUES ($1)}, [value])
  end

  # Runs one conversion's whole table of values, and reports every disagreement at once
  # rather than dying on the first - a cast matrix is read as a table, so it fails as one.
  defp assert_conversions(source_type, target_type, cases) do
    table = "cast_probe"
    column = "value"

    mismatches =
      Enum.flat_map(cases, fn {value, expected} ->
        seed_row(table, column, source_type, value)

        refused = refused?(table, column, source_type, target_type)
        converts = converts?(table, column, target_type)

        actual = if refused, do: :refuses, else: :converts

        cond do
          actual != expected ->
            ["#{inspect(value)}: expected the check to #{expected}, it #{actual}"]

          not refused and not converts ->
            ["#{inspect(value)}: the check passed it and the cast refused it"]

          true ->
            []
        end
      end)

    assert mismatches == []
  end

  describe "cast_check_statement/4 over real rows" do
    test "counts the text rows that are not an int8", %{scratch: scratch} do
      route(scratch, fn ->
        assert_conversions("text", "int8", [
          {"0", :converts},
          {"42", :converts},
          {"-42", :converts},
          {"+5", :converts},
          {"007", :converts},
          {" 12 ", :converts},
          {"9223372036854775807", :converts},
          {"-9223372036854775808", :converts},
          {"9223372036854775808", :refuses},
          {"-9223372036854775809", :refuses},
          {"99999999999999999999", :refuses},
          {String.duplicate("0", 30) <> "5", :converts},
          {long_digits(200_000), :refuses},
          {"", :refuses},
          {"abc", :refuses},
          {"1.5", :refuses},
          {"1e3", :refuses},
          {"NaN", :refuses},
          {"Infinity", :refuses}
        ])
      end)
    end

    test "counts the text rows that are not a float8", %{scratch: scratch} do
      route(scratch, fn ->
        assert_conversions("text", "float8", [
          {"0", :converts},
          {"0.0", :converts},
          {".0", :converts},
          {"-0", :converts},
          {"0e-400", :converts},
          {"0e1000000", :converts},
          {"1.5", :converts},
          {"-1.5", :converts},
          {"5.", :converts},
          {".5", :converts},
          {"1e3", :converts},
          {" 2.5 ", :converts},
          {"1e308", :converts},
          {"1e-320", :converts},
          {"inf", :converts},
          {" inf ", :converts},
          {"-Infinity", :converts},
          {"NaN", :converts},
          {"1.8e308", :refuses},
          {"1e400", :refuses},
          {"1e-400", :refuses},
          {"1e1000000", :refuses},
          {long_digits(200_000) <> ".5", :refuses},
          {"", :refuses},
          {"abc", :refuses},
          {"1,5", :refuses}
        ])
      end)
    end

    test "counts the float8 rows that are not a whole int8", %{scratch: scratch} do
      route(scratch, fn ->
        assert_conversions("float8", "int8", [
          {0.0, :converts},
          {42.0, :converts},
          {-42.0, :converts},
          {9.2e18, :converts},
          {-9.2e18, :converts},
          {-9_223_372_036_854_775_808.0, :converts},
          {1.5, :refuses},
          {-0.5, :refuses},
          {9_223_372_036_854_775_807.0, :refuses},
          {9.3e18, :refuses},
          {-9.3e18, :refuses},
          {:NaN, :refuses},
          {:inf, :refuses},
          {:"-inf", :refuses}
        ])
      end)
    end

    test "counts the timestamptz rows that are not a whole date", %{scratch: scratch} do
      route(scratch, fn ->
        {:ok, _result} = Connection.query("SET TIME ZONE 'UTC'")

        assert_conversions("timestamptz", "date", [
          {~U[2026-08-20 00:00:00.000000Z], :converts},
          {~U[1970-01-01 00:00:00.000000Z], :converts},
          {~U[2026-08-20 10:30:00.000000Z], :refuses},
          {~U[2026-08-20 00:00:00.000001Z], :refuses}
        ])
      end)
    end
  end
end
