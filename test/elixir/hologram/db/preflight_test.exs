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

    test "raises on a cast with no supported conversion" do
      ops = [alter_column_op("uuid", "int8")]

      expected_msg =
        ~s(changing column "estimate" on table "task" from uuid to int8 is not supported - ) <>
          "remove the attribute and re-add it with the new type"

      assert_error RuntimeError, expected_msg, fn -> run!(ops, %{}, mapping(nil)) end
    end
  end
end
