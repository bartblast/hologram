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
  # The invalid index is reached the way a crash reaches it, not by writing the catalog:
  # a unique build over rows that duplicate a key fails, and what it leaves behind is what
  # a killed build leaves behind.
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

  @global_grant_statement """
  INSERT INTO "hologram_data"."hologram_role_grant"
    ("id", "user_id", "role", "created_at", "updated_at", "$revisions")
  VALUES (gen_random_uuid(), $1, 'editor', now(), now(), '{}')
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
    statement = """
    INSERT INTO "hologram_data"."my_app_task" ("id", "slug", "created_at", "updated_at", "$revisions")
    VALUES (gen_random_uuid(), $1, now(), now(), '{}')
    """

    {:ok, _result} = Connection.query(statement, [slug])
  end

  defp migration(version, ops) do
    %{version: version, path: "app/migrations/#{version}.ex", ops: ops}
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

    @duplicate_slug_msg ~s{found 1 duplicate key in "my_app_task" over ("slug") - a unique index cannot be built while rows repeat a key - update the rows or drop the unique declaration}

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
  end
end
