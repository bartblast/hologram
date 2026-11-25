defmodule Hologram.Migration.Value.LoaderTest do
  # async: false, as every module of the scratch tier, which opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migration.Value.Loader
  import Hologram.Migrator

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @ops [
    %{op: :create_entity, entity: MyApp.Tag, line: 1},
    %{op: :add_attribute, entity: MyApp.Tag, name: :name, type: :string, opts: [], line: 2},
    %{op: :create_entity, entity: MyApp.User, line: 3},
    %{op: :add_attribute, entity: MyApp.User, name: :name, type: :string, opts: [], line: 4},
    %{op: :create_entity, entity: MyApp.Trip, line: 5},
    %{
      op: :add_attribute,
      entity: MyApp.Trip,
      name: :title,
      type: :string,
      opts: [optional: true],
      line: 6
    },
    %{
      op: :add_attribute,
      entity: MyApp.Trip,
      name: :state,
      type: :enum,
      opts: [optional: true, values: [:draft, :live]],
      line: 7
    },
    %{
      op: :add_attribute,
      entity: MyApp.Trip,
      name: :starts_on,
      type: :date,
      opts: [optional: true],
      line: 8
    },
    %{
      op: :add_relationship,
      entity: MyApp.Trip,
      name: :owner,
      type: MyApp.User,
      opts: [optional: true],
      line: 9
    },
    %{
      op: :add_relationship,
      entity: MyApp.Trip,
      name: :parent,
      type: MyApp.Trip,
      opts: [optional: true],
      line: 10
    },
    %{
      op: :add_relationship,
      entity: MyApp.Trip,
      name: :tags,
      type: [MyApp.Tag],
      opts: [],
      line: 11
    }
  ]

  defp insert(table, fields) do
    id = Entity.generate_id()

    names = [
      "id",
      "created_at",
      "server_created_at",
      "server_updated_at",
      "updated_at",
      "$revisions"
    ]

    custom = Map.keys(fields)
    columns = Enum.map_join(names ++ custom, ", ", &Mapper.quote_identifier/1)

    slots =
      custom
      |> Enum.with_index(2)
      |> Enum.map_join(", ", fn {_name, n} -> "$#{n}" end)

    separator = if custom == [], do: "", else: ", "

    statement = """
    INSERT INTO "hologram_data"."#{table}" (#{columns})
    VALUES ($1, now(), now(), now(), now(), '{}'#{separator}#{slots})
    """

    {:ok, _result} =
      Connection.query(statement, [Codec.encode(id, :uuid) | Enum.map(custom, &fields[&1])])

    id
  end

  defp insert_edge(table, source_id, target_id) do
    {:ok, _result} =
      Connection.query(
        ~s|INSERT INTO "hologram_data"."#{table}" ("source_id", "target_id") VALUES ($1, $2)|,
        [Codec.encode(source_id, :uuid), Codec.encode(target_id, :uuid)]
      )
  end

  defp prepare do
    model = Model.fold(Model.empty(), @ops)

    :ok =
      run([%{version: "20260813091522", path: "app/migrations/x.ex", ops: @ops}], model, @context)

    Mapper.derive_from_model!(model)
  end

  defp trip_with_tag(scratch) do
    route(scratch, fn ->
      mapping = prepare()
      tag = insert("my_app_tag", %{"name" => "a"})
      id = insert("my_app_trip", %{"title" => "x"})

      insert_edge(hd(mapping[MyApp.Trip].join_tables).name, id, tag)

      {mapping, id, tag}
    end)
  end

  # Runs the given load in a session of its own while another session deletes the row's only tag:
  # the load reads the row and its edges, then waits on the tag table until the delete commits.
  defp load_across_delete(context, mapping, id, tag, load_fun) do
    %{scratch_opts: scratch_opts} = context
    join_table = hd(mapping[MyApp.Trip].join_tables).name

    {:ok, writer} = Postgrex.start_link(scratch_opts)

    Postgrex.query!(writer, "BEGIN", [])

    Postgrex.query!(
      writer,
      ~s(LOCK TABLE "hologram_data"."my_app_tag" IN ACCESS EXCLUSIVE MODE),
      []
    )

    Postgrex.query!(writer, ~s(DELETE FROM "hologram_data"."#{join_table}"), [])

    Postgrex.query!(writer, ~s(DELETE FROM "hologram_data"."my_app_tag" WHERE "id" = $1), [
      uuid(tag)
    ])

    task =
      Task.async(fn ->
        {:ok, reader} = Postgrex.start_link(scratch_opts)

        route(reader, fn -> load_fun.(id) end)
      end)

    wait_for_blocked_sessions(scratch_opts, 1)

    Postgrex.query!(writer, "COMMIT", [])

    Task.await(task)
  end

  defp uuid(id), do: Codec.encode(id, :uuid)

  describe "load/4, the rows pointing at this one" do
    test "holds them under the type and the to-one, none included", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        parent = insert("my_app_trip", %{"title" => "parent"})
        childless = insert("my_app_trip", %{"title" => "childless"})

        child_a =
          insert("my_app_trip", %{"parent_id" => Codec.encode(parent, :uuid), "title" => "a"})

        child_b =
          insert("my_app_trip", %{"parent_id" => Codec.encode(parent, :uuid), "title" => "b"})

        reads = %{{MyApp.Trip, :parent} => %{}}

        assert [parent_row, childless_row] = load(reads, MyApp.Trip, [parent, childless], mapping)

        children = Map.fetch!(parent_row, {MyApp.Trip, :parent})

        ids = Enum.map(children, & &1.id)
        titles = Enum.map(children, & &1.title)

        assert Enum.sort(ids) == Enum.sort([child_a, child_b])
        assert Enum.sort(titles) == ["a", "b"]
        assert Map.fetch!(childless_row, {MyApp.Trip, :parent}) == []
      end)
    end
  end

  describe "load/4" do
    test "reads the row's fields in their native values", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()

        id =
          insert("my_app_trip", %{
            "title" => "Porto",
            "state" => "live",
            "starts_on" => ~D[2026-01-02]
          })

        assert [row] = load(%{}, MyApp.Trip, [id], mapping)

        assert row.id == id
        assert row.title == "Porto"
        assert row.state == :live
        assert row.starts_on == ~D[2026-01-02]
        assert row.owner_id == nil
        assert %DateTime{} = row.created_at
        assert %DateTime{} = row.updated_at
        assert %DateTime{} = row.server_created_at
        assert %DateTime{} = row.server_updated_at
      end)
    end

    test "leaves the companions and revisions out of the row", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        id = insert("my_app_trip", %{"title" => "Porto"})

        assert [row] = load(%{}, MyApp.Trip, [id], mapping)

        keys = Map.keys(row)

        assert Enum.sort(keys) ==
                 Enum.sort([
                   :created_at,
                   :id,
                   :owner_id,
                   :parent_id,
                   :server_created_at,
                   :server_updated_at,
                   :starts_on,
                   :state,
                   :title,
                   :updated_at
                 ])
      end)
    end

    test "keeps the order of the ids and leaves out one no row holds", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        first = insert("my_app_trip", %{"title" => "a"})
        second = insert("my_app_trip", %{"title" => "b"})
        missing = Entity.generate_id()

        rows = load(%{}, MyApp.Trip, [second, missing, first], mapping)

        assert Enum.map(rows, & &1.id) == [second, first]
      end)
    end

    test "finds the row of an id spelled without dashes", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        id = insert("my_app_trip", %{"title" => "a"})

        rows = load(%{}, MyApp.Trip, [String.replace(id, "-", "")], mapping)

        assert Enum.map(rows, & &1.id) == [id]
      end)
    end

    test "gives nothing for no ids", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()

        assert load(%{}, MyApp.Trip, [], mapping) == []
      end)
    end

    test "reads a to-one's row under its name", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        user = insert("my_app_user", %{"name" => "Ana"})
        id = insert("my_app_trip", %{"owner_id" => uuid(user)})

        assert [row] = load(%{owner: %{}}, MyApp.Trip, [id], mapping)

        assert row.owner_id == user
        assert row.owner.id == user
        assert row.owner.name == "Ana"
      end)
    end

    test "gives nil for a nil reference", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        id = insert("my_app_trip", %{"title" => "a"})

        assert [%{owner: nil}] = load(%{owner: %{}}, MyApp.Trip, [id], mapping)
      end)
    end

    test "reads through two hops, on a self-relationship", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        user = insert("my_app_user", %{"name" => "Ana"})
        parent = insert("my_app_trip", %{"owner_id" => uuid(user)})
        id = insert("my_app_trip", %{"parent_id" => uuid(parent)})

        assert [row] = load(%{parent: %{owner: %{}}}, MyApp.Trip, [id], mapping)

        assert row.parent.id == parent
        assert row.parent.owner.name == "Ana"
      end)
    end

    test "reads a stored to-many's rows as a list", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        first_tag = insert("my_app_tag", %{"name" => "a"})
        second_tag = insert("my_app_tag", %{"name" => "b"})
        id = insert("my_app_trip", %{"title" => "x"})
        join_table = hd(mapping[MyApp.Trip].join_tables).name

        insert_edge(join_table, id, first_tag)
        insert_edge(join_table, id, second_tag)

        assert [row] = load(%{tags: %{}}, MyApp.Trip, [id], mapping)

        names = Enum.map(row.tags, & &1.name)

        assert Enum.sort(names) == ["a", "b"]
      end)
    end

    test "gives an empty list for a to-many with no rows", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        id = insert("my_app_trip", %{"title" => "x"})

        assert [%{tags: []}] = load(%{tags: %{}}, MyApp.Trip, [id], mapping)
      end)
    end

    test "reads a to-many through a to-one", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        tag = insert("my_app_tag", %{"name" => "a"})
        parent = insert("my_app_trip", %{"title" => "p"})
        id = insert("my_app_trip", %{"parent_id" => uuid(parent)})
        join_table = hd(mapping[MyApp.Trip].join_tables).name

        insert_edge(join_table, parent, tag)

        assert [row] = load(%{parent: %{tags: %{}}}, MyApp.Trip, [id], mapping)

        assert [%{name: "a"}] = row.parent.tags
      end)
    end

    test "reads one snapshot, so a delete committing mid-load doesn't show", context do
      {mapping, id, tag} = trip_with_tag(context.scratch)

      rows =
        load_across_delete(context, mapping, id, tag, fn trip_id ->
          load(%{tags: %{}}, MyApp.Trip, [trip_id], mapping)
        end)

      assert [%{tags: [%{name: "a"}]}] = rows
    end

    test "inside a caller's transaction, drops a target deleted mid-load", context do
      {mapping, id, tag} = trip_with_tag(context.scratch)

      result =
        load_across_delete(context, mapping, id, tag, fn trip_id ->
          Connection.transaction(fn -> load(%{tags: %{}}, MyApp.Trip, [trip_id], mapping) end)
        end)

      assert {:ok, [%{tags: []}]} = result
    end

    test "shares a related row between the rows reading it", %{scratch: scratch} do
      route(scratch, fn ->
        mapping = prepare()
        user = insert("my_app_user", %{"name" => "Ana"})
        first = insert("my_app_trip", %{"owner_id" => uuid(user)})
        second = insert("my_app_trip", %{"owner_id" => uuid(user)})

        assert [%{owner: %{name: "Ana"}}, %{owner: %{name: "Ana"}}] =
                 load(%{owner: %{}}, MyApp.Trip, [first, second], mapping)
      end)
    end
  end
end
