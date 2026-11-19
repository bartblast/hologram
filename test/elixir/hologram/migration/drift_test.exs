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
  # The order is what makes the carve-out work: the repair runs BEFORE the drift check inside one
  # boot, so a missing index is rebuilt and then found present - on a chain holding every applied
  # version, since one lacking some checks first (see that describe below). Reverse the two and a dropped index
  # refuses the boot it was supposed to survive (see the index recovery tests). The index plan's
  # indexes are neither: the boot leaves them to Hologram.DB.IndexBuilder, which these tests run
  # where a state needs the plan's indexes standing.
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
  alias Hologram.DB.IndexBuilder
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # The index plan's for the reference the chain declares - the only index here besides the
  # primary key.
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
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  # What the index builder does once a node serves: the plan's indexes for the given chain's model.
  defp build_plan_indexes(chain, model) do
    plan =
      model
      |> Mapper.derive_from_model!()
      |> IndexPlan.framework_plan()

    :ok = IndexBuilder.converge(plan, chain, step_pause_ms: 0)
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
      build_plan_indexes([create], model)
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

    test "passes a deploy over a plan index dropped by hand, leaving it to the index builder", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{@index}"})

        assert run(chain, model, @context) == :ok

        assert index_validity() == :absent
      end)
    end
  end

  describe "run/3 with an object under a name the naming rule no longer derives" do
    @old_index "my_app_task_old_$idx"

    defp index_names(table \\ "my_app_task") do
      statement = """
      SELECT ic."relname"
      FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
      JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
      JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
      WHERE n."nspname" = 'hologram_data' AND c."relname" = $1 AND NOT i."indisprimary"
      ORDER BY ic."relname"
      """

      {:ok, %{rows: rows}} = Connection.query(statement, [table])

      Enum.map(rows, fn [name] -> name end)
    end

    defp rename_index_to_old_name do
      rename = ~s{ALTER INDEX "hologram_data"."#{@index}" RENAME TO "#{@old_index}"}
      {:ok, _result} = Connection.query(rename)
    end

    test "leaves a plan index under an old name to the index builder", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename_index_to_old_name()

        assert run(chain, model, @context) == :ok

        assert index_names() == [@old_index]
      end)
    end

    test "applies a pending migration deleting a relationship whose plan index stands under an old name",
         %{
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

    test "refuses a hand-made index beside a plan index under an old name", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename_index_to_old_name()

        hand_made = ~s{CREATE INDEX "rogue_index" ON "hologram_data"."my_app_task" ("created_at")}
        {:ok, _result} = Connection.query(hand_made)

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * index "rogue_index" is not derived from the model
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        ExUnit.CaptureLog.capture_log(fn ->
          assert_error RuntimeError, expected_msg, fn -> run(chain, model, @context) end
        end)

        assert index_names() == [@old_index, "rogue_index"]
      end)
    end

    test "renames a join table and its constraints, keeping the links, and leaves its reverse index to the index builder",
         %{
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
        build_plan_indexes(chain, model)

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

        assert length(renamed_lines) == 5
        assert log =~ ~s(Hologram: renamed table "#{old_table}" to "#{join_table}")
        assert log =~ ~s(Hologram: renamed constraint "my_app_task_old_$pk" to "my_app_task_$pk")

        {:ok, %{rows: rows}} =
          Connection.query(~s{SELECT count(*) FROM "hologram_data"."#{join_table}"})

        assert rows == [[1]]

        build_plan_indexes(chain, model)

        assert index_names(join_table) == ["#{join_table}_target_id_source_id_$idx"]
      end)
    end

    test "renames nothing on a node whose chain lacks an applied version", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      newer =
        migration("20260814091522", [
          %{op: :create_entity, entity: MyApp.Project, line: 3},
          %{
            op: :add_relationship,
            entity: MyApp.Project,
            name: :owner,
            type: MyApp.User,
            opts: [optional: true],
            line: 4
          }
        ])

      newer_chain = Enum.concat(chain, [newer])
      newer_model = Model.fold(model, newer.ops)

      route(scratch, fn ->
        :ok = run(newer_chain, newer_model, @context)
        build_plan_indexes(newer_chain, newer_model)

        rename_pk =
          ~s{ALTER TABLE "hologram_data"."my_app_task" RENAME CONSTRAINT "my_app_task_$pk" TO "my_app_task_old_$pk"}

        {:ok, _result} = Connection.query(rename_pk)

        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise RuntimeError, ~r/schema drift detected/, fn ->
            run(chain, model, @context)
          end
        end)

        {:ok, %{rows: rows}} =
          Connection.query("""
          SELECT con."conname"
          FROM pg_catalog.pg_constraint con
          JOIN pg_catalog.pg_class c ON c.oid = con."conrelid"
          WHERE c."relname" = 'my_app_task' AND con."contype" = 'p'
          """)

        assert rows == [["my_app_task_old_$pk"]]

        # Nor does it touch the plan's indexes: the newer release's index stays, as does the older
        # one.
        assert index_names("my_app_project") == ["my_app_project_owner_id_$idx"]
        assert index_names() == [@index]
      end)
    end
  end

  describe "run/3 with an applied version the chain doesn't hold" do
    # A missing unique index can be one a crash left unbuilt or one the newer version dropped on
    # purpose, and the node can't tell which - so it builds neither, since an index the newer version
    # dropped would refuse its writes, or fail to build over the duplicates it allowed.
    test "refuses rather than build a unique index the version it lacks dropped", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      code =
        migration("20260814091522", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :code,
            type: :string,
            opts: [optional: true, unique: true],
            line: 3
          }
        ])

      not_unique =
        migration("20260815091522", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :code,
            changes: [unique: false],
            line: 3
          }
        ])

      code_chain = Enum.concat(chain, [code])
      code_model = Model.fold(model, code.ops)
      newer_chain = Enum.concat(code_chain, [not_unique])
      newer_model = Model.fold(code_model, not_unique.ops)

      route(scratch, fn ->
        :ok = run(newer_chain, newer_model, @context)

        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise RuntimeError,
                       ~r/index "my_app_task_code_\$uidx" declared by the model is missing/,
                       fn -> run(code_chain, code_model, @context) end
        end)

        refute "my_app_task_code_$uidx" in index_names()
      end)
    end

    test "refuses with the drift message before building an index on a column it lacks", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260814091522", [
          %{op: :delete_relationship, entity: MyApp.Task, name: :author, line: 3}
        ])

      route(scratch, fn ->
        ExUnit.CaptureLog.capture_log(fn ->
          :ok = run(Enum.concat(chain, [drop]), Model.fold(model, drop.ops), @context)
        end)

        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise RuntimeError,
                       ~r/column "author_id" on table "my_app_task" declared by the model is missing/,
                       fn ->
                         run(chain, model, @context)
                       end
        end)
      end)
    end
  end

  describe "run/3 with a column dropped by hand" do
    test "refuses with the drift message rather than build the column's index", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        {:ok, _result} =
          Connection.query(~s{ALTER TABLE "hologram_data"."my_app_task" DROP COLUMN "author_id"})

        assert_raise RuntimeError,
                     ~r/column "author_id" on table "my_app_task" declared by the model is missing/,
                     fn ->
                       run(chain, model, @context)
                     end
      end)
    end
  end

  describe "check_drift!/1 with a hand-made unique index under the plan's kind" do
    test "refuses it, since the plan builds no unique index", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        unique =
          ~s{CREATE UNIQUE INDEX "rogue_$idx" ON "hologram_data"."my_app_task" ("id", "created_at")}

        {:ok, _result} = Connection.query(unique)

        expected_msg =
          normalize_newlines("""
          schema drift detected - the database does not match the model:
            * index "rogue_$idx" is not derived from the model
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        assert_error RuntimeError, expected_msg, fn -> check_drift!(mapping) end
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
          hologram_data is model-managed - restore what is missing, remove what was added by hand, or express the change as a migration\
          """)

        assert_error RuntimeError, expected_msg, fn -> run(chain, model, @context) end
      end)
    end
  end

  describe "check_drift!/1" do
    test "leaves the index plan's index to the plan, under whatever name it stands", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        rename = ~s{ALTER INDEX "hologram_data"."#{@index}" RENAME TO "my_app_task_old_$idx"}
        {:ok, _result} = Connection.query(rename)

        assert check_drift!(mapping) == :ok

        {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."my_app_task_old_$idx"})

        assert check_drift!(mapping) == :ok
      end)
    end
  end
end
