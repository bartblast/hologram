defmodule Hologram.Migration.DriftTest do
  # What a deploy does when the database is not what the model derives. Two answers, and the
  # difference between them is the whole of the carve-out: everything is REPORTED, indexes are
  # REPAIRED.
  #
  # Indexes earn the exception because they carry no data, the model is their only author, and
  # refusing instead would wedge every node of a fleet behind a state nothing can reach on its
  # own - a node that died between a file's commit and its index build leaves exactly that.
  # Anything else that differs is something a hand did, and a hand undoes it.
  #
  # The order is what makes the carve-out work, and it is what these tests pin: the repair runs
  # BEFORE the drift check inside one boot, so a missing index is rebuilt and then found present.
  # Reverse the two and a dropped index refuses the boot it was supposed to survive.
  #
  # The sandboxed suite covers the drift check called directly, which is enough to pin its
  # messages. What it cannot do is reach either behaviour through a real boot: the drift has to
  # be COMMITTED to be there when the deploy looks, and the repair builds concurrently, which
  # cannot run inside a transaction at all.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # Derived for the relationship the chain declares - the model's only index here.
  @index "my_app_task_author_id_$idx"

  defp index_validity do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Connection.query(statement, [@index]) do
      {:ok, %{rows: [[valid?]]}} -> valid?
      {:ok, %{rows: []}} -> :absent
    end
  end

  defp migration(version, ops) do
    %{version: version, path: "#{version}.exs", ops: ops}
  end

  setup %{scratch: scratch} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [optional: true],
          line: 5
        }
      ])

    model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn ->
      :ok = run([create], model, @context)
    end)

    [chain: [create], mapping: Mapper.derive_from_model!(model), model: model]
  end

  describe "run/3" do
    test "refuses a deploy over an object added by hand, naming it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        add_column = ~s{ALTER TABLE "hologram_data"."my_app_task" ADD COLUMN "rogue" text}
        {:ok, _result} = Connection.query(add_column)

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * column "rogue" on table "my_app_task" is not derived from the model
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        assert_error RuntimeError, expected_msg, fn -> run(chain, model, @context) end
      end)
    end

    test "rebuilds an index dropped by hand rather than refusing", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})

        assert index_validity() == :absent

        # The same difference that refuses as a column converges as an index: the deploy
        # completes, because the repair ran before the check and left nothing to report.
        assert run(chain, model, @context) == :ok

        assert index_validity() == true
      end)
    end
  end
end
