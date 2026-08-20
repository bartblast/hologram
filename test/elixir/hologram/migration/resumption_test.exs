defmodule Hologram.Migration.ResumptionTest do
  # What a deploy killed between two files leaves behind, and what the next one does with
  # it. The state is planted rather than raced - per-file transactions leave nothing in
  # between, so a database with the prefix applied IS a database whose applier died after
  # the prefix committed.
  #
  # The scratch tier is what makes it reachable: the rows a resumed file backfills have to
  # have been COMMITTED by an earlier apply, which the sandboxed tier cannot do - its one
  # never-committed transaction wraps every apply the test makes.
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

  # The second deploy's own context. Its timestamp is what tells a re-recorded file from an
  # untouched one: a version keeping the first run's time was not written again.
  @next_context %{@context | timestamp: ~U[2026-08-14 17:41:09.000000Z]}

  defp applied_migration_rows do
    statement = """
    SELECT "version", "applied_at" FROM "hologram_system"."migration" ORDER BY "version"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [version, applied_at] -> {version, applied_at} end)
  end

  defp insert_task(title) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [title])
  end

  defp insert_task(title, priority) do
    statement = """
    INSERT INTO "hologram_data"."my_app_task"
      ("id", "title", "priority", "created_at", "updated_at")
    VALUES (gen_random_uuid(), $1, $2, now(), now())
    """

    {:ok, _result} = Connection.query(statement, [title, priority])
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  defp task_rows do
    statement = """
    SELECT "title", "priority" FROM "hologram_data"."my_app_task" ORDER BY "title"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows
  end

  setup do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [],
          line: 4
        }
      ])

    backfilled =
      migration("20260813142237", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [backfill: 7],
          line: 3
        }
      ])

    first_model = Model.fold(Model.empty(), create.ops)
    full_model = Model.fold(first_model, backfilled.ops)

    [
      chain: [create, backfilled],
      first_model: first_model,
      full_model: full_model,
      prefix: [create]
    ]
  end

  describe "run/3" do
    test "resumes at the first file the interrupted deploy had not applied", %{
      chain: chain,
      first_model: first_model,
      full_model: full_model,
      prefix: prefix,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run(prefix, first_model, @context) == :ok

        # Committed by the interrupted deploy, and the rows the resumed file has to carry
        # forward - a backfill that fills the past is only observable on a row that
        # predates the column.
        insert_task("existing")

        assert run(chain, full_model, @next_context) == :ok

        assert task_rows() == [["existing", 7]]

        # Each file recorded exactly once, and the prefix keeps the time the interrupted
        # deploy wrote: the resumed run started at the first pending file rather than
        # replaying one already recorded.
        assert applied_migration_rows() == [
                 {"20260813091522", @context.timestamp},
                 {"20260813142237", @next_context.timestamp}
               ]
      end)
    end

    test "applies nothing when the chain is already complete", %{
      chain: chain,
      full_model: full_model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert run(chain, full_model, @context) == :ok

        # Distinct from the file's backfill, so what the assertion names could only have
        # been written here.
        insert_task("untouched", 999)

        assert run(chain, full_model, @next_context) == :ok

        assert task_rows() == [["untouched", 999]]

        assert applied_migration_rows() == [
                 {"20260813091522", @context.timestamp},
                 {"20260813142237", @context.timestamp}
               ]
      end)
    end
  end
end
