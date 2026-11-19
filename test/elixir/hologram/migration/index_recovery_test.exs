defmodule Hologram.Migration.IndexRecoveryTest do
  # The two states a deploy can die in that leave an index unfinished, and what the next
  # boot does with each: the index is ABSENT when the node died before its build began, and
  # INVALID when it died partway. Neither heals on its own - the file is recorded as
  # applied, so no later boot revisits it, and an invalid index still reads as present to
  # the drift check.
  #
  # Structurally unreachable from the sandboxed tier, which is why the repair path shipped
  # with only its no-op cases covered: a concurrent build refuses to run inside a
  # transaction and waits on every other transaction that could see the table, and the
  # sandbox is made of both. Everything here is a real build against committed rows.
  #
  # The invalid index is reached the way a crash reaches it where a build can reach it: a
  # unique build over rows that duplicate a key fails, and what it leaves behind is what a
  # killed build leaves behind. Two states are written into the catalog instead (see
  # set_index_ready/2). An invalid index that still takes writes, which a build leaves only
  # when a repeat lands between its snapshot and its check of the rows - reaching it for real
  # takes two writers held across the build's two waits, told apart by its progress. And an
  # invalid index holding the name of one a file builds over a column it adds, which no build
  # can leave, since the column isn't there before the file.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  # The one unique index the model derives: the grant fact, with nulls compared as values.
  @index "hologram_role_grant_user_id_entity_type_entity_id_role_$uidx"

  @index_op %{
    op: :create_index,
    table: "hologram_role_grant",
    index: @index,
    columns: ["user_id", "entity_type", "entity_id", "role"],
    nulls_distinct: false,
    unique: true
  }

  @duplicate_grant_msg ~s{found 1 duplicate key in "hologram_role_grant" over ("user_id", "entity_type", "entity_id", "role") - a unique index cannot be built while rows repeat a key - update the rows or drop the unique declaration}

  @duplicate_slug_msg ~s{found 1 duplicate key in "my_app_task" over ("slug") - a unique index cannot be built while rows repeat a key - update the rows or drop the unique declaration}

  @global_grant_statement """
  INSERT INTO "hologram_data"."hologram_role_grant"
    ("id", "user_id", "role", "created_at", "updated_at", "$revisions")
  VALUES (gen_random_uuid(), $1, 'editor', now(), now(), '{}')
  """

  @task_statement """
  INSERT INTO "hologram_data"."my_app_task" ("id", "slug", "created_at", "updated_at", "$revisions")
  VALUES (gen_random_uuid(), $1, now(), now(), '{}')
  """

  defp build_index_concurrently(op \\ @index_op) do
    concurrent_op = Map.put(op, :concurrently, true)
    [statement] = DDL.statements(concurrent_op)

    Connection.query(statement)
  end

  defp delete_all_rows_but_one(table) do
    statement = """
    DELETE FROM "hologram_data"."#{table}"
    WHERE "id" NOT IN (SELECT "id" FROM "hologram_data"."#{table}" LIMIT 1)
    """

    {:ok, _result} = Connection.query(statement)
  end

  defp drop_index(index \\ @index) do
    {:ok, _result} = Connection.query(~s{DROP INDEX "hologram_data"."#{index}"})
  end

  defp grant_count do
    statement = ~s{SELECT COUNT(*) FROM "hologram_data"."hologram_role_grant"}

    {:ok, %{rows: [[count]]}} = Connection.query(statement)

    count
  end

  # Every index of the table but the primary key's, valid or not, so a leftover copy shows.
  defp index_names(table) do
    statement = """
    SELECT ic."relname"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    WHERE c."relname" = $1 AND NOT i."indisprimary"
    ORDER BY ic."relname"
    """

    {:ok, %{rows: rows}} = Connection.query(statement, [table])

    Enum.map(rows, fn [index] -> index end)
  end

  # Tells the index a refusal left alone from one dropped and built again under its name.
  defp index_oid(index \\ @index) do
    {:ok, %{rows: [[oid]]}} =
      Connection.query(~s{SELECT '"hologram_data"."#{index}"'::regclass::oid})

    oid
  end

  # :absent, false (a build died partway) or true (the index serves queries).
  defp index_validity(index \\ @index) do
    statement = """
    SELECT i."indisvalid"
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ic ON ic.oid = i."indexrelid"
    JOIN pg_catalog.pg_class c ON c.oid = i."indrelid"
    JOIN pg_catalog.pg_namespace n ON n.oid = c."relnamespace"
    WHERE n."nspname" = 'hologram_data' AND ic."relname" = $1
    """

    case Connection.query(statement, [index]) do
      {:ok, %{rows: [[valid?]]}} -> valid?
      {:ok, %{rows: []}} -> :absent
    end
  end

  # A global grant - both resource columns nil - so two of them collide only because the
  # index compares nulls as values.
  defp insert_global_grant(user_id) do
    {:ok, _result} = Connection.query(@global_grant_statement, [Ecto.UUID.dump!(user_id)])
  end

  # What a node that is still running does while the index is missing: nothing stops it from
  # writing a grant that repeats the key.
  defp insert_repeated_grants(user_id) do
    insert_user(user_id)

    # Two global grants of the same role to the same user: identical on every indexed
    # column, nils included, which the index refuses only because it compares nulls as
    # values. Written through SQL - the grant API refuses the second one.
    insert_global_grant(user_id)
    insert_global_grant(user_id)
  end

  defp insert_user(user_id) do
    statement = """
    INSERT INTO "hologram_data"."my_app_user" ("id", "created_at", "updated_at", "$revisions")
    VALUES ($1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [Ecto.UUID.dump!(user_id)])
  end

  defp insert_task(slug) do
    {:ok, _result} = Connection.query(@task_statement, [slug])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
  end

  # Marks the index invalid and stops or restarts writes going through it - a superuser's
  # catalog write, which the test user is. The flag is re-read by every later statement.
  defp set_index_ready(index, ready?) do
    {:ok, _result} =
      Connection.query(
        """
        UPDATE pg_catalog.pg_index SET "indisvalid" = false, "indisready" = $1
        WHERE "indexrelid" = '"hologram_data"."#{index}"'::regclass
        """,
        [ready?]
      )
  end

  # What a concurrent drop killed after it marked the index dead leaves: writes skip the index
  # from then on, and so does a table rewrite, unless it converts a column the index covers.
  defp set_index_dead(index) do
    {:ok, _result} =
      Connection.query("""
      UPDATE pg_catalog.pg_index SET "indisvalid" = false, "indisready" = false, "indislive" = false
      WHERE "indexrelid" = '"hologram_data"."#{index}"'::regclass
      """)
  end

  setup %{scratch: scratch} do
    create =
      migration("20260813091522", [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 5},
        %{op: :designate_user_entity, entity: MyApp.User, line: 6}
      ])

    model = Model.fold(Model.empty(), create.ops)

    route(scratch, fn ->
      :ok = run([create], model, @context)
    end)

    [chain: [create], mapping: Mapper.derive_from_model!(model), model: model]
  end

  describe "repair_indexes/1" do
    test "builds an index the deploy never got to", %{mapping: mapping, scratch: scratch} do
      route(scratch, fn ->
        # What a node killed before its build began leaves: the file is recorded applied,
        # and the index the model derives is simply not there.
        drop_index()

        assert index_validity() == :absent

        assert repair_indexes(mapping) == :ok

        assert index_validity() == true
      end)
    end

    test "rebuilds an index a failed build left invalid", %{mapping: mapping, scratch: scratch} do
      user_id = "00000000-0000-0000-0000-0000000000a1"

      route(scratch, fn ->
        derived_names = index_names("hologram_role_grant")

        drop_index()
        insert_repeated_grants(user_id)

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently()

        # The state a node killed mid-build leaves behind, reached by a build that really
        # failed: the index holds the name and serves no query.
        assert index_validity() == false

        delete_all_rows_but_one("hologram_role_grant")

        assert grant_count() == 1

        assert repair_indexes(mapping) == :ok

        assert index_validity() == true

        # Dropped and built again under its own name, so no copy is left beside it - a REINDEX
        # CONCURRENTLY builds one, which stays behind when it fails.
        assert index_names("hologram_role_grant") == derived_names
      end)
    end

    # The repair's own drop, killed after it marked the index dead: the next boot drops it
    # again and builds it.
    test "rebuilds an index a killed drop left dead", %{mapping: mapping, scratch: scratch} do
      route(scratch, fn ->
        set_index_dead(@index)

        assert repair_indexes(mapping) == :ok

        assert index_validity() == true
      end)
    end

    test "refuses to build a missing unique index while rows repeat its key", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        drop_index()
        insert_repeated_grants("00000000-0000-0000-0000-0000000000a1")

        names = index_names("hologram_role_grant")

        assert_error RuntimeError, @duplicate_grant_msg, fn -> repair_indexes(mapping) end

        # Refused before the build, so no failed build is left holding the name.
        assert index_validity() == :absent
        assert index_names("hologram_role_grant") == names

        # Every boot until the rows are fixed refuses the same way, and adds nothing.
        assert_error RuntimeError, @duplicate_grant_msg, fn -> repair_indexes(mapping) end

        assert index_names("hologram_role_grant") == names
      end)
    end

    test "refuses to rebuild an invalid unique index while rows repeat its key", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        derived_names = index_names("hologram_role_grant")

        drop_index()
        insert_repeated_grants("00000000-0000-0000-0000-0000000000a1")

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently()

        oid = index_oid()

        assert_error RuntimeError, @duplicate_grant_msg, fn -> repair_indexes(mapping) end

        # Left as it was found - the same index, not one dropped and failed again under its
        # name - still invalid, and no copy beside it.
        assert index_oid() == oid
        assert index_validity() == false
        assert index_names("hologram_role_grant") == derived_names

        assert_error RuntimeError, @duplicate_grant_msg, fn -> repair_indexes(mapping) end

        assert index_oid() == oid
        assert index_names("hologram_role_grant") == derived_names
      end)
    end

    # A running node writes the repeated key after the repair counted and before its build
    # finished. The build waits for every transaction that could see the table to end, so a
    # write left open across the count lands exactly there.
    test "refuses when a key repeats while the build runs", %{
      mapping: mapping,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      user_id = "00000000-0000-0000-0000-0000000000a1"
      test_pid = self()

      route(scratch, fn ->
        drop_index()
        insert_user(user_id)
        insert_global_grant(user_id)
      end)

      {:ok, writer_connection} = Postgrex.start_link(scratch_opts)

      writer =
        Task.async(fn ->
          Postgrex.transaction(writer_connection, fn connection ->
            Postgrex.query!(connection, @global_grant_statement, [Ecto.UUID.dump!(user_id)])
            send(test_pid, :written)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :written, 5_000

      repair =
        Task.async(fn ->
          route(scratch, fn ->
            assert_error RuntimeError, @duplicate_grant_msg, fn -> repair_indexes(mapping) end
          end)
        end)

      wait_for_blocked_sessions(scratch_opts, 1)

      send(writer.pid, :commit)
      assert {:ok, :ok} = Task.await(writer)

      Task.await(repair)

      # The failed build holds the name, which the next boot's repair counts before it touches.
      route(scratch, fn ->
        assert index_validity() == false
      end)
    end

    test "leaves an invalid index the model does not derive alone", %{
      mapping: mapping,
      scratch: scratch
    } do
      extra_index = "hologram_role_grant_extra_$uidx"

      route(scratch, fn ->
        # Two grants of one role to two users, which the derived index allows.
        for user_id <- [
              "00000000-0000-0000-0000-0000000000a1",
              "00000000-0000-0000-0000-0000000000a2"
            ] do
          insert_user(user_id)
          insert_global_grant(user_id)
        end

        extra_op = %{@index_op | index: extra_index, columns: ["role"]}

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently(extra_op)

        assert repair_indexes(mapping) == :ok

        assert index_validity(extra_index) == false
        assert index_validity() == true
      end)
    end

    # The repair builds the model's definition, so rebuilding a hand-made index that only
    # shares the name would replace it with another one. The drift check names it instead.
    test "leaves an invalid index under a derived name with another definition alone", %{
      mapping: mapping,
      scratch: scratch
    } do
      route(scratch, fn ->
        drop_index()

        for user_id <- [
              "00000000-0000-0000-0000-0000000000a1",
              "00000000-0000-0000-0000-0000000000a2"
            ] do
          insert_user(user_id)
          insert_global_grant(user_id)
        end

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently(%{@index_op | columns: ["role"]})

        oid = index_oid()

        assert repair_indexes(mapping) == :ok

        assert index_oid() == oid
        assert index_validity() == false
      end)
    end
  end

  describe "run/3 with a tail build" do
    # A file's tail builds after the file commits, and meets an invalid index under the name
    # only when one stood there before the file applied - the index of a crashed deploy is the
    # repair's, since the file is no longer pending.
    test "drops an invalid index holding the name before building", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      add_slug =
        migration("20260813091523", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :slug,
            type: :string,
            opts: [optional: true, unique: true],
            line: 3
          }
        ])

      slug_index = "my_app_task_slug_$uidx"

      route(scratch, fn ->
        {:ok, _result} =
          Connection.query(
            ~s{CREATE INDEX "#{slug_index}" ON "hologram_data"."my_app_task" ("created_at")}
          )

        {:ok, _result} =
          Connection.query("""
          UPDATE pg_catalog.pg_index SET "indisvalid" = false
          WHERE "indexrelid" = '"hologram_data"."#{slug_index}"'::regclass
          """)

        assert index_validity(slug_index) == false

        assert run(Enum.concat(chain, [add_slug]), Model.fold(model, add_slug.ops), @context) ==
                 :ok

        assert index_validity(slug_index) == true
      end)
    end

    # The file's check counts the rows before it commits, and nothing enforces the key until
    # its tail's build finishes, so a running node can write a repeat in between. A write left
    # open across the check lands exactly there: the build waits for it to end.
    test "refuses when a key repeats between the file's check and its build", %{
      chain: chain,
      model: model,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      add_slug =
        migration("20260813091523", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :slug,
            type: :string,
            opts: [optional: true],
            line: 3
          }
        ])

      make_unique =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: true],
            line: 3
          }
        ])

      slug_chain = Enum.concat(chain, [add_slug])
      slug_model = Model.fold(model, add_slug.ops)
      test_pid = self()

      route(scratch, fn ->
        :ok = run(slug_chain, slug_model, @context)
        insert_task("taken")
      end)

      {:ok, writer_connection} = Postgrex.start_link(scratch_opts)

      writer =
        Task.async(fn ->
          Postgrex.transaction(writer_connection, fn connection ->
            Postgrex.query!(connection, @task_statement, ["taken"])
            send(test_pid, :written)

            receive do
              :commit -> :ok
            end
          end)
        end)

      assert_receive :written, 5_000

      boot =
        Task.async(fn ->
          route(scratch, fn ->
            assert_error RuntimeError, @duplicate_slug_msg, fn ->
              run(
                Enum.concat(slug_chain, [make_unique]),
                Model.fold(slug_model, make_unique.ops),
                @context
              )
            end
          end)
        end)

      wait_for_blocked_sessions(scratch_opts, 1)

      send(writer.pid, :commit)
      assert {:ok, :ok} = Task.await(writer)

      Task.await(boot)

      # The file committed before its build, which failed holding the name for the next
      # boot's repair to count.
      route(scratch, fn ->
        assert make_unique.version in applied_versions()
        assert index_validity("my_app_task_slug_$uidx") == false
      end)
    end
  end

  # A later release meeting the index an interrupted deploy left unfinished: its file renames
  # or drops an index that a build never started, or one that a failed build left invalid.
  describe "run/3" do
    @slug_index "my_app_task_slug_$uidx"

    @slug_index_op %{
      op: :create_index,
      table: "my_app_task",
      index: @slug_index,
      columns: ["slug"],
      nulls_distinct: true,
      unique: true
    }

    @invalid_slug_msg ~s{found 1 duplicate key in "my_app_task" over ("slug") - the unique index over it is not built yet, and a type change on the table rebuilds it - update the rows}

    @drop_unique_slug %{
      version: "20260813091525",
      path: "app/migrations/20260813091525.ex",
      ops: [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :slug,
          changes: [unique: false],
          line: 3
        }
      ]
    }

    @checking_slug_msg ~s{found 1 duplicate key in "my_app_task" over ("slug") - the unique index over it is not built yet, but it already checks the rows this file writes - update the rows}

    setup %{chain: chain, model: model, scratch: scratch} do
      # A unique column added to a table that predates the file, so its index builds
      # concurrently, after the file commits.
      add_slug =
        migration("20260813091523", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :slug,
            type: :string,
            opts: [optional: true, unique: true],
            line: 3
          }
        ])

      slug_chain = Enum.concat(chain, [add_slug])
      slug_model = Model.fold(model, add_slug.ops)

      route(scratch, fn ->
        :ok = run(slug_chain, slug_model, @context)
      end)

      [chain: slug_chain, model: slug_model]
    end

    # Nothing pending: the repair after the files meets the index the deploy never built, over
    # rows a running node wrote meanwhile.
    test "refuses while rows repeat a missing index's key, and boots once they no longer do", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      route(scratch, fn ->
        derived_names = index_names("my_app_task")

        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert_error RuntimeError, @duplicate_slug_msg, fn -> run(chain, model, @context) end
        assert_error RuntimeError, @duplicate_slug_msg, fn -> run(chain, model, @context) end

        delete_all_rows_but_one("my_app_task")

        # The drift check passes too: nothing the failed boots did is left to clean up.
        assert run(chain, model, @context) == :ok

        assert index_validity(@slug_index) == true
        assert index_names("my_app_task") == derived_names
      end)
    end

    test "builds an index a deploy never got to before a pending file renames it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      rename =
        migration("20260813091524", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}
        ])

      post_model = Model.fold(model, rename.ops)

      route(scratch, fn ->
        # What a node killed after the file committed and before its build began leaves.
        drop_index(@slug_index)

        assert run(Enum.concat(chain, [rename]), post_model, @context) == :ok

        assert index_validity("my_app_task_handle_$uidx") == true
        assert index_validity(@slug_index) == :absent
      end)
    end

    test "builds an index a deploy never got to before a pending file drops it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: false],
            line: 3
          }
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        drop_index(@slug_index)

        assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The repair would refuse to rebuild the index while rows repeat its key, and it doesn't
    # need to: the index holds its name, so the pending drop finds it and takes it away.
    test "leaves an index a failed build left invalid to the pending file that drops it", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      drop =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: false],
            line: 3
          }
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
                 build_index_concurrently(@slug_index_op)

        assert index_validity(@slug_index) == false

        assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # A running node wrote the repeated key while the index was missing. The build before the
    # pending files fails on it and leaves the name taken, which is what the pending drop needs.
    test "boots on the first try when a pending file drops a missing index whose key repeats",
         %{chain: chain, model: model, scratch: scratch} do
      drop =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [unique: false],
            line: 3
          }
        ])

      post_model = Model.fold(model, drop.ops)

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert run(Enum.concat(chain, [drop]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The table's drop takes the index with it whether or not the build ran, so this one guards
    # only that the failed build doesn't stop the boot.
    test "boots on the first try when a pending file deletes the entity of a missing index " <>
           "whose key repeats",
         %{chain: chain, model: model, scratch: scratch} do
      delete =
        migration("20260813091524", [%{op: :delete_entity, entity: MyApp.Task, line: 3}])

      post_model = Model.fold(model, delete.ops)

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert run(Enum.concat(chain, [delete]), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The pending file keeps the index under a new name, so the repair after it refuses there.
    test "refuses a missing index whose key repeats after a pending file renames it, and " <>
           "boots once the key no longer repeats",
         %{chain: chain, model: model, scratch: scratch} do
      rename =
        migration("20260813091524", [
          %{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}
        ])

      renamed_chain = Enum.concat(chain, [rename])
      post_model = Model.fold(model, rename.ops)
      handle_index = "my_app_task_handle_$uidx"

      expected_msg =
        ~s{found 1 duplicate key in "my_app_task" over ("handle") - a unique index cannot be built while rows repeat a key - update the rows or drop the unique declaration}

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert_error RuntimeError, expected_msg, fn ->
          run(renamed_chain, post_model, @context)
        end

        # A rename leaves the rows as they are, so the pending file applied, and the failed
        # build it renamed holds the new name.
        assert "20260813091524" in applied_versions()
        assert index_validity(handle_index) == false

        assert_error RuntimeError, expected_msg, fn ->
          run(renamed_chain, post_model, @context)
        end

        delete_all_rows_but_one("my_app_task")

        assert run(renamed_chain, post_model, @context) == :ok

        assert index_validity(handle_index) == true
      end)
    end

    # The pass before the pending files leaves the index invalid over the repeated key, and a
    # type change on its table rebuilds every index there - this one included, which fails.
    test "refuses a pending type change on the table of a missing index whose key repeats", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {extra_chain, extra_model} = apply_extra_attributes(chain, model, scratch)

      change =
        migration("20260813091525", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer],
            line: 3
          }
        ])

      assert_refused_with_invalid_index(scratch, extra_chain, extra_model, change)
    end

    test "refuses a pending enum rebuild on the table of a missing index whose key repeats", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {extra_chain, extra_model} = apply_extra_attributes(chain, model, scratch)

      delete_value =
        migration("20260813091525", [
          %{
            op: :delete_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            value: :done,
            line: 3
          }
        ])

      assert_refused_with_invalid_index(scratch, extra_chain, extra_model, delete_value)
    end

    # A slug every row can convert, so the cast's own row check passes, and the refusal names
    # the repeat the rows already hold rather than one the cast would make.
    test "refuses a pending type change on the column of a missing index whose key repeats", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      change =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [type: :integer],
            line: 3
          }
        ])

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("1")
        insert_task("1")

        assert_error RuntimeError, @invalid_slug_msg, fn ->
          run(Enum.concat(chain, [change]), Model.fold(model, change.ops), @context)
        end

        refute "20260813091524" in applied_versions()
      end)
    end

    # A repeat a running node writes while a concurrent build runs, after the build took its
    # snapshot and before it checked the rows, fails the build in its last phase. The index it
    # leaves is invalid and serves no query, but writes already go through it, and a write
    # that puts a row with the repeated key back into it fails. Staged in the catalog, which
    # leaves the same index behind with one writer instead of two: the index stops taking
    # writes, the repeat is written past it, and it takes writes again.
    test "refuses a pending fill on the table of an invalid index still checking writes", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {extra_chain, extra_model} = apply_extra_attributes(chain, model, scratch)

      fill =
        migration("20260813091525", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false, default: "none"],
            line: 3
          }
        ])

      assert_refused_with_checking_index(scratch, extra_chain, extra_model, fill)
    end

    test "refuses a pending required attribute on the table of an invalid index still " <>
           "checking writes",
         %{chain: chain, model: model, scratch: scratch} do
      add =
        migration("20260813091524", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [default: 5],
            line: 3
          }
        ])

      assert_refused_with_checking_index(scratch, chain, model, add)
    end

    # The build before the pending files fails over the repeat while building, which leaves
    # an index that takes no writes. Fills go past it, and the later file that drops the
    # unique declaration takes it away.
    test "boots on the first try when pending fills pass an invalid index taking no writes", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      fills =
        migration("20260813091524", [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [default: 5],
            line: 3
          },
          # Two rows without a slug take the same one, a repeat of its own - one only a valid
          # index would refuse.
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [optional: false, default: "filled"],
            line: 4
          }
        ])

      pending = [fills, @drop_unique_slug]
      post_model = Enum.reduce(pending, model, &Model.fold(&2, &1.ops))

      route(scratch, fn ->
        drop_index(@slug_index)
        insert_task("taken")
        insert_task("taken")
        insert_task(nil)
        insert_task(nil)

        assert run(Enum.concat(chain, pending), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The rewrite passes over a dead index off the column it converts, and the later file drops
    # it, so the repeat it never refused doesn't matter.
    test "boots on the first try when a pending type change meets an index a killed drop left " <>
           "dead",
         %{chain: chain, model: model, scratch: scratch} do
      {extra_chain, extra_model} = apply_extra_attributes(chain, model, scratch)

      change =
        migration("20260813091525", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [type: :integer],
            line: 3
          }
        ])

      drop_unique = migration("20260813091526", @drop_unique_slug.ops)
      pending = [change, drop_unique]
      post_model = Enum.reduce(pending, extra_model, &Model.fold(&2, &1.ops))

      route(scratch, fn ->
        set_index_dead(@slug_index)
        insert_task("taken")
        insert_task("taken")

        assert run(Enum.concat(extra_chain, pending), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end

    # The type change builds an index over its column again from the definition, a dead one
    # included, and that build fails over the repeat.
    test "refuses a pending type change on the column of an index a killed drop left dead", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      change =
        migration("20260813091524", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :slug,
            changes: [type: :integer],
            line: 3
          }
        ])

      route(scratch, fn ->
        set_index_dead(@slug_index)
        insert_task("1")
        insert_task("1")

        assert_error RuntimeError, @invalid_slug_msg, fn ->
          run(Enum.concat(chain, [change]), Model.fold(model, change.ops), @context)
        end

        refute "20260813091524" in applied_versions()
      end)
    end

    # The tightening writes only the rows without an amount, and the repeated rows hold one,
    # so its fill never puts the repeated key back into the index.
    test "boots on the first try when a pending tightening writes none of the repeated rows", %{
      chain: chain,
      model: model,
      scratch: scratch
    } do
      {extra_chain, extra_model} = apply_extra_attributes(chain, model, scratch)

      fill =
        migration("20260813091525", [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :amount,
            changes: [optional: false, default: "none"],
            line: 3
          }
        ])

      drop_unique = migration("20260813091526", @drop_unique_slug.ops)
      pending = [fill, drop_unique]
      post_model = Enum.reduce(pending, extra_model, &Model.fold(&2, &1.ops))

      route(scratch, fn ->
        insert_task("taken")
        set_index_ready(@slug_index, false)
        insert_task("taken")

        {:ok, _result} =
          Connection.query(
            ~s{UPDATE "hologram_data"."my_app_task" SET "amount" = 'set' WHERE "slug" = 'taken'}
          )

        set_index_ready(@slug_index, true)
        insert_task("other")

        assert run(Enum.concat(extra_chain, pending), post_model, @context) == :ok

        assert index_validity(@slug_index) == :absent
      end)
    end
  end

  # Two optional attributes the rows leave NULL, which any type change or enum rebuild takes.
  defp apply_extra_attributes(chain, model, scratch) do
    extra =
      migration("20260813091524", [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :amount,
          type: :string,
          opts: [optional: true],
          line: 3
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :status,
          type: :enum,
          opts: [values: [:done, :todo], optional: true],
          line: 4
        }
      ])

    extra_chain = Enum.concat(chain, [extra])
    extra_model = Model.fold(model, extra.ops)

    route(scratch, fn ->
      :ok = run(extra_chain, extra_model, @context)
    end)

    {extra_chain, extra_model}
  end

  # The repeat goes in first, so the rows written after it fill its page: a fill of a column no
  # index covers then can't keep the row's new version on that page, and has to write it into
  # every index. A fill of an indexed column writes into every index anyway.
  defp assert_refused_with_checking_index(scratch, chain, model, pending) do
    pending_chain = Enum.concat(chain, [pending])
    post_model = Model.fold(model, pending.ops)

    route(scratch, fn ->
      insert_task("taken")
      set_index_ready(@slug_index, false)
      insert_task("taken")
      set_index_ready(@slug_index, true)

      Enum.each(1..300, &insert_task("filler-#{&1}"))

      assert_error RuntimeError, @checking_slug_msg, fn ->
        run(pending_chain, post_model, @context)
      end

      refute pending.version in applied_versions()

      {:ok, _result} =
        Connection.query(~s{DELETE FROM "hologram_data"."my_app_task" WHERE "slug" = 'taken'})

      assert run(pending_chain, post_model, @context) == :ok

      assert index_validity(@slug_index) == true
    end)
  end

  defp assert_refused_with_invalid_index(scratch, chain, model, pending) do
    route(scratch, fn ->
      drop_index(@slug_index)
      insert_task("taken")
      insert_task("taken")

      assert_error RuntimeError, @invalid_slug_msg, fn ->
        run(Enum.concat(chain, [pending]), Model.fold(model, pending.ops), @context)
      end

      # Refused before the change, which the file's transaction takes back.
      refute pending.version in applied_versions()
      assert index_validity(@slug_index) == false

      delete_all_rows_but_one("my_app_task")

      assert run(Enum.concat(chain, [pending]), Model.fold(model, pending.ops), @context) == :ok

      assert index_validity(@slug_index) == true
    end)
  end
end
