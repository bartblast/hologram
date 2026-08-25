defmodule Hologram.Migration.SortKeyFillTest do
  # The fill of a sort-key companion a migration adds to a table that already holds rows.
  #
  # The scratch tier is what makes the question askable. Under the sandbox every row a test
  # writes lives in the same never-committed transaction as the apply that is supposed to
  # find them "already there", so a fill of pre-existing rows cannot be told from a fill of
  # the test's own uncommitted ones.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp insert_tasks(column, values) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "#{column}", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), '{}')
    """

    Enum.each(values, fn value ->
      {:ok, _result} = Connection.query(statement, [value])
    end)
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp task_rows(columns) do
    statement =
      ~s(SELECT #{columns} FROM "hologram_data"."my_app_task" ORDER BY #{columns})

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  describe "run/3" do
    test "fills the sort-key companion a migration adds to a table holding rows", %{
      scratch: scratch
    } do
      route(scratch, fn ->
        create =
          migration("20260813091522", [
            %{op: :create_entity, entity: MyApp.Task, line: 3},
            %{
              op: :add_attribute,
              entity: MyApp.Task,
              name: :priority,
              type: :integer,
              opts: [],
              line: 4
            }
          ])

        first_model = Model.fold(Model.empty(), create.ops)

        assert run([create], first_model, @context) == :ok

        insert_tasks("priority", [1, 2])

        add_title =
          migration("20260813142237", [
            %{
              op: :add_attribute,
              entity: MyApp.Task,
              name: :title,
              type: :string,
              opts: [backfill: "Zoe"],
              line: 3
            }
          ])

        full_model = Model.fold(first_model, add_title.ops)

        assert run([create, add_title], full_model, @context) == :ok

        assert task_rows(~s("title", "title_$sort")) == [["Zoe", "zoe"], ["Zoe", "zoe"]]
      end)
    end

    test "fills the companion of an attribute a migration casts to string", %{
      scratch: scratch
    } do
      route(scratch, fn ->
        create =
          migration("20260813091522", [
            %{op: :create_entity, entity: MyApp.Task, line: 3},
            %{
              op: :add_attribute,
              entity: MyApp.Task,
              name: :code,
              type: :integer,
              opts: [],
              line: 4
            }
          ])

        first_model = Model.fold(Model.empty(), create.ops)

        assert run([create], first_model, @context) == :ok

        insert_tasks("code", [10, 9])

        cast_code =
          migration("20260813142237", [
            %{
              op: :change_attribute,
              entity: MyApp.Task,
              name: :code,
              changes: [type: :string],
              line: 3
            }
          ])

        full_model = Model.fold(first_model, cast_code.ops)

        assert run([create, cast_code], full_model, @context) == :ok

        assert task_rows(~s("code", "code_$sort")) == [["10", "10"], ["9", "9"]]
      end)
    end
  end
end
