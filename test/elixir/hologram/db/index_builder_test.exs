defmodule Hologram.DB.IndexBuilderTest do
  # What the index builder does to the index plan's indexes once a node serves: the boot leaves
  # them out, and the builder builds, renames and drops them one step at a time under the migration
  # lock. Concurrent builds and drops can't run inside a transaction, so this runs on a scratch
  # database of its own.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection, so the
  # tier's modules run one at a time to keep the server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.DB.IndexBuilder

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Migrator

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # The index plan's for the reference the chain declares.
  @index "my_app_task_author_id_$idx"

  @editor_index "my_app_task_editor_id_$idx"

  # The value of Hologram.Migrator's @advisory_lock_key, hardcoded for the reason the lock
  # contention tests give: the key is frozen forever.
  @migration_lock_key -335_777_576_117_788_795

  # The value of Hologram.Migrator's @boot_lock_key, hardcoded for the same reason.
  @boot_lock_key -8_943_570_201_190_700_407

  # Whether a session on the given session's database holds the boot key - read here rather than
  # through Hologram.Migrator.boot_key_held?/0, which is part of what the tests check.
  defp boot_key_held?(session) do
    statement = """
    SELECT EXISTS (
      SELECT 1 FROM pg_catalog.pg_locks
      WHERE "locktype" = 'advisory' AND "objsubid" = 1
        AND "database" = (
          SELECT "oid" FROM pg_catalog.pg_database WHERE "datname" = current_database()
        )
        AND (("classid"::bigint << 32) | "objid"::bigint) = $1
    )
    """

    %{rows: [[held?]]} = Postgrex.query!(session, statement, [@boot_lock_key])

    held?
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  defp plan(model) do
    model
    |> Mapper.derive_from_model!()
    |> IndexPlan.framework_plan()
  end

  # :absent, false (a build died partway) or true (the index serves queries).
  defp index_validity(index) do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = ic."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Connection.query(statement, [index]) do
      {:ok, %{rows: [[valid?]]}} -> valid?
      {:ok, %{rows: []}} -> :absent
    end
  end

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

  defp index_oid(name) do
    {:ok, %{rows: [[oid]]}} =
      Connection.query(
        ~s{SELECT c.oid FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace" WHERE n."nspname" = 'hologram_data' AND c."relname" = $1},
        [name]
      )

    oid
  end

  # Whether the given session takes the migration lock within the given wall-clock time, trying
  # until then. A lock taken late is let go and counts as not taken: a try that resumes after the
  # deadline can catch, in the moment it lets the lock go, a builder that held it through the pause.
  defp take_lock_within(session, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    try_until(session, deadline)
  end

  defp try_until(session, deadline) do
    %{rows: [[locked?]]} =
      Postgrex.query!(session, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

    late? = System.monotonic_time(:millisecond) > deadline

    cond do
      locked? and late? ->
        Postgrex.query!(session, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])
        false

      locked? ->
        true

      late? ->
        false

      true ->
        try_until(session, deadline)
    end
  end

  # Starts the given run/1 call as a task the test awaits, killed when the test ends: run/1 traps
  # exits, so a linked task would outlive a test that fails before awaiting it, retrying against a
  # dropped database.
  defp start_run(fun) do
    supervisor = start_supervised!(Task.Supervisor)
    Task.Supervisor.async_nolink(supervisor, fun, shutdown: :brutal_kill)
  end

  defp query!(statement) do
    {:ok, _result} = Connection.query(statement)
  end

  defp rename_index(from, to) do
    query!(~s{ALTER INDEX "hologram_data"."#{from}" RENAME TO "#{to}"})
  end

  # The info lines the builder logs. The suite runs at :warning, and the module is async: false, so
  # raising the level for one run touches no other test.
  defp capture_info(fun) do
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: level)
    end
  end

  defp fold_chain(chain, model, migration) do
    {Enum.concat(chain, [migration]), Model.fold(model, migration.ops)}
  end

  # Adds an optional editor to-one beside the author, its migration applied and its index built,
  # and returns the chain and the model it leaves.
  defp with_editor(chain, model, scratch) do
    editor =
      migration("20260814091522", [
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :editor,
          type: MyApp.User,
          opts: [optional: true],
          line: 3
        }
      ])

    editor_chain = Enum.concat(chain, [editor])
    editor_model = Model.fold(model, editor.ops)

    route(scratch, fn ->
      :ok = Migrator.run(editor_chain, editor_model, @context)
      :ok = converge(plan(editor_model), editor_chain, step_pause_ms: 0)
    end)

    {editor_chain, editor_model}
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
      :ok = Migrator.run([create], model, @context)
    end)

    [chain: [create], model: model]
  end

  describe "converge/3" do
    test "builds the plan's index the boot left out", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        assert index_validity(@index) == :absent

        log = capture_info(fn -> assert converge(plan(model), chain, step_pause_ms: 0) == :ok end)

        assert log =~ ~s(Hologram: built index "#{@index}", which the queries need)
        assert index_validity(@index) == true
      end)
    end

    test "drops an index a build left invalid and builds it again", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      blocker = start_supervised!({Postgrex, scratch_opts}, id: :blocker)
      builder = start_supervised!({Postgrex, scratch_opts}, id: :builder)

      # A build kept waiting by an open transaction that could write its table, then cancelled: what
      # a build that dies partway leaves behind. ROW EXCLUSIVE is what a write takes, and a concurrent
      # build waits for every such holder once its catalog entry, flagged invalid, is committed.
      Postgrex.query!(blocker, "BEGIN", [])

      Postgrex.query!(
        blocker,
        ~s{LOCK TABLE "hologram_data"."my_app_task" IN ROW EXCLUSIVE MODE},
        []
      )

      build =
        Task.async(fn ->
          Postgrex.query(
            builder,
            ~s{CREATE INDEX CONCURRENTLY "#{@index}" ON "hologram_data"."my_app_task" ("author_id")},
            []
          )
        end)

      wait_for_blocked_sessions(scratch_opts, 1)

      Postgrex.query!(
        blocker,
        ~s{SELECT pg_cancel_backend("pid") FROM pg_catalog.pg_stat_activity WHERE "datname" = current_database() AND "query" LIKE 'CREATE INDEX CONCURRENTLY%'},
        []
      )

      assert {:error, %Postgrex.Error{}} = Task.await(build)

      Postgrex.query!(blocker, "COMMIT", [])

      route(scratch, fn ->
        # A boot leaves it: an invalid plan index may be another node's build in flight.
        assert Migrator.run(chain, model, @context) == :ok
        assert index_validity(@index) == false

        log = capture_info(fn -> assert converge(plan(model), chain, step_pause_ms: 0) == :ok end)

        assert log =~ ~s(Hologram: dropped index "#{@index}", which a build left invalid)
        assert index_validity(@index) == true
      end)
    end

    test "renames an index the plan names standing under another name, building no copy", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        :ok = converge(plan(model), chain, step_pause_ms: 0)

        rename_index(@index, "my_app_task_old_$idx")
        oid = index_oid("my_app_task_old_$idx")

        log = capture_info(fn -> assert converge(plan(model), chain, step_pause_ms: 0) == :ok end)

        assert log =~
                 ~s(Hologram: renamed index "my_app_task_old_$idx" to "#{@index}" to follow the current naming rule)

        assert index_names() == [@index]
        assert index_oid(@index) == oid
      end)
    end

    test "renames two indexes whose names swapped, rebuilding neither", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {editor_chain, editor_model} = with_editor(chain, model, scratch)

      route(scratch, fn ->
        author_oid = index_oid(@index)
        editor_oid = index_oid(@editor_index)

        for {from, to} <- [{@index, "swap"}, {@editor_index, @index}, {"swap", @editor_index}] do
          rename_index(from, to)
        end

        assert converge(plan(editor_model), editor_chain, step_pause_ms: 0) == :ok

        assert index_oid(@index) == author_oid
        assert index_oid(@editor_index) == editor_oid
      end)
    end

    test "renames along a chain whose names the plan wants in turn", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {editor_chain, editor_model} = with_editor(chain, model, scratch)

      route(scratch, fn ->
        author_oid = index_oid(@index)
        editor_oid = index_oid(@editor_index)

        # The author index stands as "x", and the editor index in the author's name.
        for {from, to} <- [{@index, "my_app_task_x_$idx"}, {@editor_index, @index}] do
          rename_index(from, to)
        end

        assert converge(plan(editor_model), editor_chain, step_pause_ms: 0) == :ok

        assert index_oid(@index) == author_oid
        assert index_oid(@editor_index) == editor_oid
      end)
    end

    test "renames first the stray of a definition standing in a name the plan wants", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {editor_chain, editor_model} = with_editor(chain, model, scratch)

      route(scratch, fn ->
        author_oid = index_oid(@index)
        editor_oid = index_oid(@editor_index)

        for {from, to} <- [{@index, "my_app_task_b_$idx"}, {@editor_index, @index}] do
          rename_index(from, to)
        end

        # A second stray of the editor's definition, first by name.
        query!(
          ~s{CREATE INDEX "my_app_task_a_$idx" ON "hologram_data"."my_app_task" ("editor_id")}
        )

        assert converge(plan(editor_model), editor_chain, step_pause_ms: 0) == :ok

        assert index_names() == [@index, @editor_index]
        assert index_oid(@index) == author_oid
        assert index_oid(@editor_index) == editor_oid
      end)
    end

    test "gives up a chain of renames whose end a plan index nothing moves holds", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {editor_chain, editor_model} = with_editor(chain, model, scratch)

      route(scratch, fn ->
        for {from, to} <- [{@index, "my_app_task_x_$idx"}, {@editor_index, @index}] do
          rename_index(from, to)
        end

        query!(
          ~s{CREATE INDEX "#{@editor_index}" ON "hologram_data"."my_app_task" ("created_at")}
        )

        assert converge(plan(editor_model), editor_chain, step_pause_ms: 0) == :ok

        indexes = Introspection.schema().tables["my_app_task"].indexes

        assert index_names() == [@index, @editor_index]
        assert indexes[@index].columns == ["author_id"]
        assert indexes[@editor_index].columns == ["editor_id"]
      end)
    end

    test "leaves a target an index outside the plan holds, dropping the stray", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {editor_chain, editor_model} = with_editor(chain, model, scratch)

      route(scratch, fn ->
        rename_index(@editor_index, "my_app_task_y_$idx")

        query!(
          ~s{CREATE INDEX "#{@editor_index}" ON "hologram_data"."my_app_task" ("editor_id") WHERE "editor_id" IS NOT NULL}
        )

        assert converge(plan(editor_model), editor_chain, step_pause_ms: 0) == :ok

        assert index_names() == [@index, @editor_index]

        assert Introspection.schema().tables["my_app_task"].indexes[@editor_index][:non_plain] ==
                 [
                   :predicate
                 ]
      end)
    end

    test "drops an index the plan doesn't name", %{chain: chain, model: model, scratch: scratch} do
      route(scratch, fn ->
        query!(
          ~s{CREATE INDEX "my_app_task_created_at_$idx" ON "hologram_data"."my_app_task" ("created_at")}
        )

        log = capture_info(fn -> assert converge(plan(model), chain, step_pause_ms: 0) == :ok end)

        assert log =~
                 ~s(Hologram: dropped index "my_app_task_created_at_$idx", which no query and no lookup needs)

        assert index_names() == [@index]
      end)
    end

    test "builds an index that replaces another before it drops the other", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      wider_index = "my_app_task_author_id_id_$idx"

      wider_plan = %{
        "my_app_task" => %{
          wider_index => %{columns: ["author_id", "id"], nulls_distinct: true, unique: false}
        }
      }

      route(scratch, fn ->
        :ok = converge(plan(model), chain, step_pause_ms: 0)

        log = capture_info(fn -> assert converge(wider_plan, chain, step_pause_ms: 0) == :ok end)

        {built_at, _length} = :binary.match(log, ~s(built index "#{wider_index}"))
        {dropped_at, _length} = :binary.match(log, ~s(dropped index "#{@index}"))

        assert built_at < dropped_at
        assert index_names() == [wider_index]
      end)
    end

    test "rebuilds an index the plan names that stands with another definition", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        query!(~s{CREATE INDEX "#{@index}" ON "hologram_data"."my_app_task" ("created_at")})

        assert converge(plan(model), chain, step_pause_ms: 0) == :ok

        assert Introspection.schema().tables["my_app_task"].indexes[@index].columns == [
                 "author_id"
               ]
      end)
    end

    test "renames a renamed to-one's index and builds the one added under its old name", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      reshuffle =
        migration("20260814091522", [
          %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator, line: 3},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [optional: true],
            line: 4
          }
        ])

      reshuffle_chain = Enum.concat(chain, [reshuffle])
      reshuffle_model = Model.fold(model, reshuffle.ops)

      route(scratch, fn ->
        :ok = converge(plan(model), chain, step_pause_ms: 0)
        oid = index_oid(@index)

        :ok = Migrator.run(reshuffle_chain, reshuffle_model, @context)

        assert converge(plan(reshuffle_model), reshuffle_chain, step_pause_ms: 0) == :ok

        # The renamed relationship's index is renamed with it, not rebuilt.
        assert index_oid("my_app_task_creator_id_$idx") == oid
        assert index_names() == [@index, "my_app_task_creator_id_$idx"]
      end)
    end

    test "on a chain lacking an applied version, builds what the plan is missing and leaves the rest, saying which versions it doesn't know",
         %{chain: chain, model: model, scratch: scratch} do
      reverted = migration("20260814091522", [])

      route(scratch, fn ->
        reverted_chain = Enum.concat(chain, [reverted])
        :ok = Migrator.run(reverted_chain, model, @context)

        # Plan-shaped, so a newer release's index as far as this node knows, and one under a name
        # the node's plan would rename.
        query!(
          ~s{CREATE INDEX "my_app_task_created_at_$idx" ON "hologram_data"."my_app_task" ("created_at")}
        )

        query!(
          ~s{CREATE INDEX "my_app_task_old_$idx" ON "hologram_data"."my_app_task" ("author_id")}
        )

        log = capture_log(fn -> assert converge(plan(model), chain, step_pause_ms: 0) == :ok end)

        assert log =~ "20260814091522"
        assert index_validity(@index) == true
        assert index_names() == [@index, "my_app_task_created_at_$idx", "my_app_task_old_$idx"]
      end)
    end

    test "waits for the migration lock before each step", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      builder =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> converge(plan(model), chain, step_pause_ms: 0) end)
        end)

      assert Task.yield(builder, 1_500) == nil

      route(scratch, fn -> assert index_validity(@index) == :absent end)

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      assert Task.await(builder, 30_000) == :ok

      route(scratch, fn -> assert index_validity(@index) == true end)
    end

    test "lets the lock go between two steps", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      created_at_index = "my_app_task_created_at_$idx"

      plan =
        model
        |> plan()
        |> put_in(["my_app_task", created_at_index], %{
          columns: ["created_at"],
          nulls_distinct: true,
          unique: false
        })

      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      builder =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> converge(plan, chain, step_pause_ms: 2_000) end)
        end)

      route(scratch, fn -> wait_until(fn -> index_validity(@index) == true end, 10_000) end)

      # Between the two steps: free for a booting node, which this one stands for. Tried for 1 s of
      # the 2 s pause, since the index stands valid a moment before the builder lets the lock go -
      # and no longer, or a builder holding the lock through the pause would let one try through
      # as it takes the lock back.
      assert take_lock_within(holder, 1_000)

      assert Task.yield(builder, 2_500) == nil
      route(scratch, fn -> assert index_validity(created_at_index) == :absent end)

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      assert Task.await(builder, 30_000) == :ok
      route(scratch, fn -> assert index_validity(created_at_index) == true end)
    end

    test "gives the lock back to a booting node waiting for it, and builds once the node is done",
         %{
           chain: chain,
           model: model,
           scratch: scratch,
           scratch_opts: scratch_opts
         } do
      boot = start_supervised!({Postgrex, scratch_opts}, id: :boot)

      assert %{rows: [[true]]} =
               Postgrex.query!(boot, "SELECT pg_try_advisory_lock_shared($1)", [@boot_lock_key])

      log =
        capture_info(fn ->
          builder =
            Task.async(fn ->
              {:ok, session} = Postgrex.start_link(scratch_opts)

              route(session, fn -> converge(plan(model), chain, step_pause_ms: 0) end)
            end)

          # Asleep before its next try, which only a builder that gave the lock back is.
          wait_until(
            fn ->
              Process.info(builder.pid, :current_function) ==
                {:current_function, {Process, :sleep, 1}}
            end,
            10_000
          )

          route(scratch, fn -> assert index_validity(@index) == :absent end)

          assert %{rows: [[true]]} =
                   Postgrex.query!(boot, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

          Postgrex.query!(boot, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])
          Postgrex.query!(boot, "SELECT pg_advisory_unlock_shared($1)", [@boot_lock_key])

          assert Task.await(builder, 30_000) == :ok
        end)

      route(scratch, fn -> assert index_validity(@index) == true end)

      assert length(String.split(log, "a booting node needs the migration lock")) == 2
    end

    # Asked before it takes the lock, a builder that missed a boot taking the key would take its
    # next step after the boot started waiting.
    test "asks whether a booting node waits once it holds the lock, not before it polls", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)
      boot = start_supervised!({Postgrex, scratch_opts}, id: :boot)

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      builder =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> converge(plan(model), chain, step_pause_ms: 0) end)
        end)

      # Polling for the lock the holder has.
      wait_until(
        fn ->
          Process.info(builder.pid, :current_function) ==
            {:current_function, {Process, :sleep, 1}}
        end,
        10_000
      )

      assert %{rows: [[true]]} =
               Postgrex.query!(boot, "SELECT pg_try_advisory_lock_shared($1)", [@boot_lock_key])

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      # Past the builder's next poll, 5 s after its first.
      Process.sleep(6_000)
      route(scratch, fn -> assert index_validity(@index) == :absent end)

      Postgrex.query!(boot, "SELECT pg_advisory_unlock_shared($1)", [@boot_lock_key])

      assert Task.await(builder, 30_000) == :ok
      route(scratch, fn -> assert index_validity(@index) == true end)
    end

    test "returns a step it took that came up again, which another node undid", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      other_node = start_supervised!({Postgrex, scratch_opts}, id: :other_node)

      builder =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> converge(plan(model), chain, step_pause_ms: 2_000) end)
        end)

      route(scratch, fn -> wait_until(fn -> index_validity(@index) == true end, 10_000) end)

      # What a builder of a release whose plan lacks the index does in the pause.
      Postgrex.query!(other_node, ~s{DROP INDEX "hologram_data"."#{@index}"}, [])

      assert {:undone, {:create, %{index: @index}}} = Task.await(builder, 30_000)
      route(scratch, fn -> assert index_validity(@index) == :absent end)
    end
  end

  describe "run/1" do
    test "tries a failed run again after the interval, until it converges", %{
      chain: chain,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      # A plan index on a json column, which btree has no operator class for - a build PostgreSQL
      # refuses until the column becomes text.
      plan = %{
        "my_app_task" => %{
          "my_app_task_blob_$idx" => %{columns: ["blob"], nulls_distinct: true, unique: false}
        }
      }

      route(scratch, fn ->
        query!(~s{ALTER TABLE "hologram_data"."my_app_task" ADD COLUMN "blob" json})
      end)

      fixer = start_supervised!({Postgrex, scratch_opts}, id: :fixer)

      log =
        capture_log(fn ->
          builder =
            start_run(fn ->
              route(scratch, fn ->
                run(plan: plan, migrations: chain, retry_interval_ms: 100, step_pause_ms: 0)
              end)
            end)

          # Asleep before its next try, so a try has failed.
          wait_until(fn ->
            Process.info(builder.pid, :current_function) ==
              {:current_function, {Process, :sleep, 1}}
          end)

          Postgrex.query!(
            fixer,
            ~s{ALTER TABLE "hologram_data"."my_app_task" ALTER COLUMN "blob" TYPE text},
            []
          )

          assert Task.await(builder, 30_000) == :ok
        end)

      assert log =~
               "Hologram: building the indexes the queries need failed, and is tried again in 100 ms"

      route(scratch, fn -> assert index_validity("my_app_task_blob_$idx") == true end)
    end

    test "backs off and converges again after another node undid a step", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      other_node = start_supervised!({Postgrex, scratch_opts}, id: :other_node)

      log =
        capture_log(fn ->
          builder =
            start_run(fn ->
              route(scratch, fn ->
                run(
                  plan: plan(model),
                  migrations: chain,
                  retry_interval_ms: 100,
                  step_pause_ms: 2_000
                )
              end)
            end)

          # Built, not merely begun: a drop meeting the build in flight deadlocks with it.
          wait_until(
            fn ->
              %{rows: rows} =
                Postgrex.query!(
                  other_node,
                  ~s{SELECT i."indisvalid" FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class c ON c.oid = i."indexrelid" WHERE c."relname" = $1},
                  [@index]
                )

              rows == [[true]]
            end,
            10_000
          )

          Postgrex.query!(other_node, ~s{DROP INDEX CONCURRENTLY "hologram_data"."#{@index}"}, [])

          assert Task.await(builder, 30_000) == :ok
        end)

      assert log =~
               ~s(Hologram: building index "#{@index}" came up again - another node, likely of another release, undid it - so building the indexes the queries need is tried again in 100 ms)

      route(scratch, fn -> assert index_validity(@index) == true end)
    end
  end

  describe "Hologram.Migrator.boot_key_held?/0" do
    test "whether a session on the current database holds the boot key", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      boot = start_supervised!({Postgrex, scratch_opts}, id: :boot)

      route(scratch, fn -> refute Migrator.boot_key_held?() end)

      assert %{rows: [[true]]} =
               Postgrex.query!(boot, "SELECT pg_try_advisory_lock_shared($1)", [@boot_lock_key])

      route(scratch, fn -> assert Migrator.boot_key_held?() end)
    end

    # pg_locks lists the locks of every database on the server.
    test "leaves out a session on another database", %{scratch: scratch} do
      other_database = start_supervised!({Postgrex, Config.connection_opts([])}, id: :other)

      assert %{rows: [[true]]} =
               Postgrex.query!(other_database, "SELECT pg_try_advisory_lock_shared($1)", [
                 @boot_lock_key
               ])

      route(scratch, fn -> refute Migrator.boot_key_held?() end)
    end
  end

  describe "Hologram.Migrator.with_migration_connection/1" do
    # A node that vanishes holding the migration lock or the boot key would otherwise hold up the
    # other nodes for hours.
    test "sets the keepalives and the user timeout of the session", %{scratch: scratch} do
      statement =
        "SELECT current_setting('tcp_keepalives_idle'), current_setting('tcp_keepalives_interval'), current_setting('tcp_keepalives_count'), current_setting('tcp_user_timeout')"

      route(scratch, fn ->
        assert {:ok, %Postgrex.Result{rows: [["30", "10", "3", user_timeout]]}} =
                 Migrator.with_migration_connection(fn -> Connection.query(statement) end)

        # A platform without the user timeout keeps it at 0.
        assert user_timeout in ["0", "60000"]
      end)
    end

    test "runs with no statement or lock timeout, whatever the database sets", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      database = Mapper.quote_identifier(scratch_opts[:database])

      # Long enough for the session's first statement, which clears them, to run under them.
      route(scratch, fn ->
        query!("ALTER DATABASE #{database} SET statement_timeout = '5min'")
        query!("ALTER DATABASE #{database} SET lock_timeout = '5min'")

        assert Migrator.with_migration_connection(fn ->
                 {:ok, %{rows: [[statement_timeout]]}} =
                   Connection.query("SHOW statement_timeout")

                 {:ok, %{rows: [[lock_timeout]]}} = Connection.query("SHOW lock_timeout")

                 {statement_timeout, lock_timeout}
               end) == {"0", "0"}
      end)
    end

    test "ends the session for good when its connection is lost", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      observer = start_supervised!({Postgrex, scratch_opts}, id: :observer)

      outcome =
        Task.async(fn ->
          Process.flag(:trap_exit, true)

          route(scratch, fn ->
            Migrator.with_migration_connection(fn ->
              {:ok, %{rows: [[backend]]}} = Connection.query("SELECT pg_backend_pid()")

              # Waits up to 5 s for the backend to end, and answers false if it hasn't by then.
              %{rows: [[true]]} =
                Postgrex.query!(observer, "SELECT pg_terminate_backend($1, 5000)", [backend])

              # No statement after it runs, on this session or a fresh one, which would hold no
              # lock: each fails or exits.
              for _attempt <- 1..3 do
                try do
                  Connection.query("SELECT pg_backend_pid()")
                catch
                  :exit, reason -> {:exit, reason}
                end
              end
            end)
          end)
        end)

      # Past the 5 s the termination can take, with room for the tries after it.
      outcomes = Task.await(outcome, 15_000)

      refute Enum.any?(outcomes, &match?({:ok, _result}, &1))
      assert {:exit, _reason} = List.last(outcomes)
    end
  end

  describe "Hologram.Migrator.run/3 beside the builder" do
    # A btree entry is capped near 2.7 kB, so an index over the raw text would refuse a long value.
    test "drops a plan index over a column a migration casts to text, and only that one", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      amount =
        migration("20260814091522", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :amount,
            type: :integer,
            opts: [optional: true],
            line: 3
          }
        ])

      to_float =
        migration("20260815091522", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :float],
            line: 3
          }
        ])

      to_string =
        migration("20260816091522", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :string],
            line: 3
          }
        ])

      amount_index = "my_app_task_amount_$idx"

      route(scratch, fn ->
        :ok = converge(plan(model), chain, step_pause_ms: 0)

        {amount_chain, amount_model} = fold_chain(chain, model, amount)
        :ok = Migrator.run(amount_chain, amount_model, @context)
        query!(~s{CREATE INDEX "#{amount_index}" ON "hologram_data"."my_app_task" ("amount")})

        # A cast to another type than text keeps it: PostgreSQL rebuilds it over the new type.
        {float_chain, float_model} = fold_chain(amount_chain, amount_model, to_float)
        assert Migrator.run(float_chain, float_model, @context) == :ok
        assert index_names() == [amount_index, @index]

        {string_chain, string_model} = fold_chain(float_chain, float_model, to_string)
        assert Migrator.run(string_chain, string_model, @context) == :ok
        assert index_names() == [@index]
      end)
    end

    test "holds the boot key while it waits for the lock, and lets it go with its session", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      title =
        migration("20260814091522", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :title,
            type: :string,
            opts: [optional: true],
            line: 3
          }
        ])

      {title_chain, title_model} = fold_chain(chain, model, title)
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      boot =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> Migrator.run(title_chain, title_model, @context) end)
        end)

      wait_until(fn -> boot_key_held?(holder) end, 10_000)
      assert Task.yield(boot, 0) == nil

      Postgrex.query!(holder, "SELECT pg_advisory_unlock($1)", [@migration_lock_key])

      assert Task.await(boot, 30_000) == :ok

      # The server frees it once the session's backend exits, a moment after the socket closes.
      wait_until(fn -> not boot_key_held?(scratch) end, 10_000)
    end

    test "boots without the lock when nothing is left to do, while a build holds it", %{
      chain: chain,
      model: model,
      scratch_opts: scratch_opts
    } do
      holder = start_supervised!({Postgrex, scratch_opts}, id: :holder)

      assert %{rows: [[true]]} =
               Postgrex.query!(holder, "SELECT pg_try_advisory_lock($1)", [@migration_lock_key])

      boot =
        Task.async(fn ->
          {:ok, session} = Postgrex.start_link(scratch_opts)

          route(session, fn -> Migrator.run(chain, model, @context) end)
        end)

      assert Task.await(boot, 5_000) == :ok
    end
  end
end
