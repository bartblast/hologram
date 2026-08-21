defmodule Hologram.DB.PreflightTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Preflight

  alias Hologram.Test.Fixtures.Entity.Module1

  defp alter_column_op(before_type, after_type) do
    %{
      op: :alter_column,
      table: "task",
      column: "estimate",
      before: %{type: before_type, collation: nil, null: false},
      after: %{type: after_type, collation: nil, null: false}
    }
  end

  defp mapping(default) do
    %{
      Module1 => %{
        table: "task",
        columns: [%{name: "estimate", type: :integer, default: default}]
      }
    }
  end

  describe "fill_value/3" do
    test "returns the encoded declared default" do
      assert fill_value(mapping(7), "task", "estimate") == {:ok, 7}
    end

    test "returns :none when the column declares no default" do
      assert fill_value(mapping(nil), "task", "estimate") == :none
    end

    test "returns :none for a column outside the mapping" do
      assert fill_value(mapping(7), "task", "unmapped") == :none
      assert fill_value(mapping(7), "unmapped", "estimate") == :none
    end
  end

  describe "run!/3" do
    test "passes a safe cast without touching the database" do
      ops = [alter_column_op("int8", "float8")]

      assert run!(ops, %{}, mapping(nil)) == :ok
    end

    test "passes ops that transform nothing" do
      ops = [%{op: :create_table, table: "task"}, %{op: :drop_index, index: "task_$idx"}]

      assert run!(ops, %{}, mapping(nil)) == :ok
    end

    test "skips the removed-value check for an enum type this run creates" do
      ops = [
        %{
          op: :rebuild_enum_type,
          enum_type: "task_status_$enum",
          values: ["done", "todo"],
          columns: [{"task", "status"}]
        }
      ]

      assert run!(ops, %{tables: %{}, enum_types: %{}}, mapping(nil)) == :ok
    end

    test "skips the duplicate check for a unique index on a table this run creates" do
      ops = [
        %{
          op: :create_index,
          table: "task",
          index: "task_slug_$uidx",
          columns: ["slug"],
          nulls_distinct: true,
          unique: true
        }
      ]

      assert run!(ops, %{tables: %{}}, mapping(nil)) == :ok
    end

    test "skips the null-tightening check for a table this run creates" do
      ops = [
        %{
          op: :alter_column,
          table: "task",
          column: "title",
          before: %{type: "text", null: true},
          after: %{type: "text", null: false}
        }
      ]

      assert run!(ops, %{tables: %{}}, mapping(nil)) == :ok
    end

    test "skips the cast check for a table this run creates" do
      ops = [alter_column_op("text", "int8")]

      assert run!(ops, %{tables: %{}}, mapping(nil)) == :ok
    end

    test "skips the required-column check for a table this run creates" do
      ops = [
        %{
          op: :add_column,
          table: "task",
          column: "title",
          definition: %{type: "text", null: false}
        }
      ]

      assert run!(ops, %{tables: %{}}, mapping(nil)) == :ok
    end

    test "skips the removed-value check for a column of a table this run creates" do
      ops = [
        %{
          op: :rebuild_enum_type,
          enum_type: "task_status_$enum",
          values: ["done"],
          columns: [{"task", "status"}]
        }
      ]

      actual = %{tables: %{}, enum_types: %{"task_status_$enum" => ["done", "todo"]}}

      assert run!(ops, actual, mapping(nil)) == :ok
    end

    # The value is not removed, it is carried to a new label - so counting the rows holding it
    # would refuse the very rename doing the carrying. Asserted without a database on purpose:
    # the table IS in the schema, so a check that ran would reach for a connection and raise.
    test "skips the removed-value check for a value an unscoped remap carries" do
      ops = [
        %{
          op: :rebuild_enum_type,
          enum_type: "task_status_$enum",
          values: ["b", "c"],
          columns: [{"task", "status"}],
          remap: [%{from: "a", to: "c", scope: nil}]
        }
      ]

      actual = %{tables: %{"task" => %{}}, enum_types: %{"task_status_$enum" => ["a", "b"]}}

      assert run!(ops, actual, mapping(nil)) == :ok
    end

    test "raises on a cast with no supported conversion" do
      ops = [alter_column_op("uuid", "int8")]

      expected_msg =
        ~s(changing column "estimate" on table "task" from uuid to int8 is not supported - ) <>
          "remove the attribute and re-add it with the new type"

      assert_error RuntimeError, expected_msg, fn -> run!(ops, %{}, mapping(nil)) end
    end
  end
end
