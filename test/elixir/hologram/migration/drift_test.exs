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

  describe "run/3 with an object under a name the naming rule no longer derives" do
    @old_index "my_app_task_old_$idx"

    defp index_names do
      statement = """
      SELECT ic."relname"
      FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
      JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
      JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
      WHERE n."nspname" = 'hologram_data' AND c."relname" = 'my_app_task' AND NOT i."indisprimary"
      ORDER BY ic."relname"
      """

      {:ok, %{rows: rows}} = Connection.query(statement)

      Enum.map(rows, fn [name] -> name end)
    end

    defp rename_index_to_old_name do
      rename = ~s{ALTER INDEX "hologram_data"."#{@index}" RENAME TO "#{@old_index}"}
      {:ok, _result} = Connection.query(rename)
    end

    test "renames the index at boot instead of building a second one", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename_index_to_old_name()

        # The suite runs at :warning, and the line is an info one. The module is async: false,
        # so raising the level for one run touches no other test.
        level = Logger.level()
        Logger.configure(level: :info)

        log =
          try do
            ExUnit.CaptureLog.capture_log([level: :info], fn ->
              assert run(chain, model, @context) == :ok
            end)
          after
            Logger.configure(level: level)
          end

        assert log =~
                 ~s(Hologram: renamed index "#{@old_index}" to "#{@index}" to follow the current naming rule)

        assert index_names() == [@index]
      end)
    end

    test "renames the index before a pending migration that drops it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260814091522", [
          %{op: :delete_relationship, entity: MyApp.Task, name: :author, line: 3}
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        rename_index_to_old_name()

        ExUnit.CaptureLog.capture_log(fn ->
          assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok
        end)

        assert index_names() == []
      end)
    end

    test "renames the index and still refuses a hand-made one beside it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename_index_to_old_name()

        hand_made = ~s{CREATE INDEX "rogue_$idx" ON "hologram_data"."my_app_task" ("created_at")}
        {:ok, _result} = Connection.query(hand_made)

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * index "rogue_$idx" is not derived from the model
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        ExUnit.CaptureLog.capture_log(fn ->
          assert_error RuntimeError, expected_msg, fn -> run(chain, model, @context) end
        end)

        assert index_names() == [@index, "rogue_$idx"]
      end)
    end

    test "renames a join table and its constraints and reverse index, keeping the links", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      watchers =
        migration("20260814091522", [
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :watchers,
            type: [MyApp.User],
            opts: [],
            line: 3
          }
        ])

      chain = Enum.concat(chain, [watchers])
      model = Model.fold(model, watchers.ops)
      join_table = "my_app_task_watchers_$join"
      old_table = "my_app_task_old_$join"

      route(scratch, fn ->
        :ok = run(chain, model, @context)

        {:ok, _result} =
          Connection.query("""
          INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", "updated_at", "$revisions")
          VALUES ('00000000-0000-0000-0000-000000000001', now(), now(), '{}')
          """)

        {:ok, _result} =
          Connection.query("""
          INSERT INTO "hologram_data"."my_app_task" ("id", "created_at", "updated_at", "$revisions")
          VALUES ('00000000-0000-0000-0000-000000000002', now(), now(), '{}')
          """)

        {:ok, _result} =
          Connection.query("""
          INSERT INTO "hologram_data"."#{join_table}" ("source_id", "target_id")
          VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
          """)

        old_names = [
          ~s{ALTER TABLE "hologram_data"."#{join_table}" RENAME TO "#{old_table}"},
          ~s{ALTER TABLE "hologram_data"."#{old_table}" RENAME CONSTRAINT "#{join_table}_$pk" TO "#{old_table}_$pk"},
          ~s{ALTER TABLE "hologram_data"."#{old_table}" RENAME CONSTRAINT "#{join_table}_source_id_$fk" TO "#{old_table}_source_id_$fk"},
          ~s{ALTER TABLE "hologram_data"."#{old_table}" RENAME CONSTRAINT "#{join_table}_target_id_$fk" TO "#{old_table}_target_id_$fk"},
          ~s{ALTER INDEX "hologram_data"."#{join_table}_target_id_source_id_$idx" RENAME TO "#{old_table}_target_id_source_id_$idx"},
          ~s{ALTER TABLE "hologram_data"."my_app_task" RENAME CONSTRAINT "my_app_task_$pk" TO "my_app_task_old_$pk"}
        ]

        Enum.each(old_names, fn statement -> {:ok, _result} = Connection.query(statement) end)

        level = Logger.level()
        Logger.configure(level: :info)

        log =
          try do
            ExUnit.CaptureLog.capture_log([level: :info], fn ->
              assert run(chain, model, @context) == :ok
            end)
          after
            Logger.configure(level: level)
          end

        renamed_lines =
          log
          |> String.split("\n")
          |> Enum.filter(&(&1 =~ "Hologram: renamed "))

        assert length(renamed_lines) == 6
        assert log =~ ~s(Hologram: renamed table "#{old_table}" to "#{join_table}")
        assert log =~ ~s(Hologram: renamed constraint "my_app_task_old_$pk" to "my_app_task_$pk")

        {:ok, %{rows: rows}} =
          Connection.query(~s{SELECT count(*) FROM "hologram_data"."#{join_table}"})

        assert rows == [[1]]
      end)
    end

    test "renames nothing on a node whose chain lacks an applied version", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      newer =
        migration("20260814091522", [
          %{op: :create_entity, entity: MyApp.Project, line: 3}
        ])

      route(scratch, fn ->
        :ok = run(Enum.concat(chain, [newer]), Model.fold(model, newer.ops), @context)

        rename_index_to_old_name()

        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise RuntimeError, fn -> run(chain, model, @context) end
        end)

        assert index_names() == [@old_index]
      end)
    end
  end

  describe "repair_indexes/1" do
    test "builds no second copy of an index standing under another name", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename = ~s{ALTER INDEX "hologram_data"."#{@index}" RENAME TO "my_app_task_old_$idx"}
        {:ok, _result} = Connection.query(rename)

        assert repair_indexes(mapping) == :ok

        {:ok, %{rows: rows}} =
          Connection.query("""
          SELECT ic."relname"
          FROM pg_catalog.pg_index i
          JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
          JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
          WHERE c."relname" = 'my_app_task' AND NOT i."indisprimary"
          """)

        assert rows == [["my_app_task_old_$idx"]]
      end)
    end
  end

  describe "run/3 with an index nothing derives" do
    test "refuses a hand-made partial index standing under the derived name", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})

        {:ok, _result} =
          Connection.query(
            ~s{CREATE INDEX "#{@index}" ON "hologram_data"."my_app_task" ("author_id") WHERE "author_id" IS NOT NULL}
          )

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * index "#{@index}" is not derived from the model (it has a predicate)
            * index "#{@index}" declared by the model is missing
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        assert_error RuntimeError, expected_msg, fn -> run(chain, model, @context) end
      end)
    end
  end

  describe "check_drift!/1" do
    test "describes an index standing under another name as a rename", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename = ~s{ALTER INDEX "hologram_data"."#{@index}" RENAME TO "my_app_task_old_$idx"}
        {:ok, _result} = Connection.query(rename)

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * index "my_app_task_old_$idx" on table "my_app_task" is named outside the derived scheme - the model derives "#{@index}"
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        assert_error RuntimeError, expected_msg, fn -> check_drift!(mapping) end
      end)
    end
  end
end
