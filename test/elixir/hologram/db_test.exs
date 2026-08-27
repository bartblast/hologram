defmodule Hologram.DBTest do
  # async: false - the boot-mechanism tests flip the HOLOGRAM_ENV env var, which is global.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB
  import Hologram.Query, only: [decrement: 3, put_attribute: 3]
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.WriteError

  describe "__using__/1" do
    test "imports the query and write stages, and aliases the modules the executors live on" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.DB.DataSurface do
          use Hologram.DB

          def query, do: filter(Hologram.Test.Fixtures.Entity.Module2, c: "abc")

          def write, do: put_attribute(Entity.new(Hologram.Test.Fixtures.Entity.Module2), :c, "abc")

          def executor, do: DB.pool_name()
        end
        """)

      assert module.query() == %Query{
               entity: Module2,
               filter: [{:c, :==, "abc"}]
             }

      assert module.write().__meta__.attribute_ops == %{c: {:put, "abc"}}
      assert module.executor() == pool_name()
    end
  end

  describe "init/1" do
    test "starts only the connection pool in test" do
      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool]
    end

    test "adds the schema reconciliation boot step in dev" do
      System.put_env("HOLOGRAM_ENV", "dev")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :schema_reconciliation]
    end

    test "adds the migration apply boot step outside dev and test" do
      System.put_env("HOLOGRAM_ENV", "prod")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      # Only dev and test carry default connection options - a prod resolve needs them
      # configured, though nothing connects here (init/1 only builds the child specs).
      database_config = Application.get_env(:hologram, :database, [])

      Application.put_env(:hologram, :database,
        database: "my_app_prod",
        host: "db.internal",
        password: "secret",
        user: "my_app"
      )

      on_exit(fn -> Application.put_env(:hologram, :database, database_config) end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :migrations]
    end
  end

  describe "mapping/0" do
    test "returns the mapping derived from the discovered entity types" do
      assert mapping() == Mapper.derive!(Reflection.list_entities())
    end
  end

  describe "pool_name/0" do
    test "names a running connection pool that executes queries" do
      assert Postgrex.query!(pool_name(), "SELECT 1", []).rows == [[1]]
    end
  end

  describe "reconciliation_context/0" do
    test "carries the mapping, guard facts, and marker diagnostics" do
      context = reconciliation_context()

      assert context.mapping == mapping()
      assert context.otp_app == "hologram"
      assert context.env == "test"
      assert context.hologram_version == Mix.Project.config()[:version]
      assert %DateTime{} = context.timestamp
    end
  end

  describe "create/1" do
    test "evaluates the claim under an acting user" do
      entity = Entity.new(Module1)

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Entity.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn -> create(entity) end)
      end
    end

    # Both shapes in one test: the first create binds {:ok, _} or the match fails, and the
    # second pins the violation travelling out through the gateway unchanged.
    test "returns the unique violation from the write itself" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      result =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      assert result == {:error, %{slug: [:unique]}}
    end

    test "returns a value violation and a taken unique value in one map" do
      {:ok, _entity} =
        Module19
        |> Entity.new(code: "gateway_taken", slug: "gateway_a")
        |> create()

      assert create(Entity.new(Module19, code: "gateway_taken", slug: 123)) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    test "returns a missing reference target" do
      assert create(Entity.new(Module3, c_id: Entity.generate_id())) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "returns every missing reference target" do
      assert create(Entity.new(Module3, b_id: Entity.generate_id(), c_id: Entity.generate_id())) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn -> create(%RoleGrant{}) end
    end
  end

  describe "create!/1" do
    test "returns the created entity" do
      entity =
        Module1
        |> Entity.new()
        |> create!()

      assert entity.created_at
      assert read(Module1, entity.id).id == entity.id
    end

    test "raises a write error naming every value violation" do
      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module2:
          * attribute :b must be of type :integer, got: "nope"
          * attribute :c is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        Module2
        |> Entity.new(b: "nope")
        |> create!()
      end

      error =
        try do
          Module2
          |> Entity.new(b: "nope")
          |> create!()
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{b: [type: :integer], c: [:required]}
    end

    # assert_error sees the message and nothing else, so the reason field - what the plain
    # variant would have returned - is caught and asserted separately.
    test "raises naming the taken value beside the value violation" do
      {:ok, _entity} =
        Module19
        |> Entity.new(code: "bang_taken", slug: "bang_a")
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :code "bang_taken" is already taken
          * attribute :slug must be of type :string, got: 123\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Entity.new(Module19, code: "bang_taken", slug: 123))
      end
    end

    test "raises a write error when a unique attribute's value is taken" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "x")
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :slug "x" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        Module19
        |> Entity.new(slug: "x")
        |> create!()
      end

      error =
        try do
          Module19
          |> Entity.new(slug: "x")
          |> create!()
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{slug: [:unique]}
    end

    test "raises naming the missing target" do
      gone_id = Entity.generate_id()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module13:
          * reference :parent_id "#{gone_id}" names no existing entity\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Entity.new(Module13, parent_id: gone_id, title: "t"))
      end

      error =
        try do
          create!(Entity.new(Module13, parent_id: gone_id, title: "t"))
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{parent_id: [:not_found]}
    end

    test "raises naming the missing target beside the value violation" do
      gone_id = Entity.generate_id()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module13:
          * reference :parent_id "#{gone_id}" names no existing entity
          * attribute :title is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Entity.new(Module13, parent_id: gone_id, title: nil))
      end
    end
  end

  describe "delete/2" do
    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        delete(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end
  end

  describe "delete/1" do
    test "deletes the given entity struct" do
      {:ok, entity} = create(Entity.new(Module1))

      assert delete(entity) == :ok
      assert read(Module1, entity.id) == nil
    end
  end

  describe "delete!/1" do
    test "deletes the given entity struct" do
      {:ok, entity} = create(Entity.new(Module1))

      assert delete!(entity) == :ok
      assert read(Module1, entity.id) == nil
    end

    test "lets a denied claim propagate" do
      {:ok, entity} = create(Entity.new(Module1))

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Entity.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn -> delete!(entity) end)
      end

      assert read(Module1, entity.id) != nil
    end

    test "raises on a restricted delete" do
      {:ok, target} = create(Entity.new(Module1))

      {:ok, source} =
        Module3
        |> Entity.new(c_id: target.id)
        |> create()

      expected_msg =
        "cannot delete Hologram.Test.Fixtures.Entity.Module1 #{inspect(target.id)} - " <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error WriteError, expected_msg, fn -> delete!(target) end

      assert read(Module3, source.id) != nil
    end

    test "raises on a restricted delete inside a transaction" do
      {:ok, target} = create(Entity.new(Module1))

      {:ok, _source} =
        Module3
        |> Entity.new(c_id: target.id)
        |> create()

      expected_msg =
        "cannot delete Hologram.Test.Fixtures.Entity.Module1 #{inspect(target.id)} - " <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error WriteError, expected_msg, fn ->
        transaction(fn -> delete!(target) end)
      end
    end
  end

  describe "delete!/2" do
    test "returns :ok" do
      {:ok, entity} =
        Module1
        |> Entity.new()
        |> create()

      assert delete!(Module1, entity.id) == :ok
      assert read(Module1, entity.id) == nil
    end

    test "raises a write error when another entity references the row" do
      {:ok, target} =
        Module1
        |> Entity.new()
        |> create()

      {:ok, _referencing} =
        Module3
        |> Entity.new(c_id: target.id)
        |> create()

      expected_msg =
        ~s(cannot delete Hologram.Test.Fixtures.Entity.Module1 "#{target.id}" - ) <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error Hologram.WriteError, expected_msg, fn ->
        delete!(Module1, target.id)
      end

      error =
        try do
          delete!(Module1, target.id)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{referenced_by: Module3, relationship: :c}
      assert read(Module1, target.id) == target
    end
  end

  describe "reload/0" do
    test "re-derives the mapping and reconciles the schema" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload() == :ok

      assert Introspection.schema() == Schema.from_mapping(mapping())
    end
  end

  describe "transaction/2" do
    test "completes a refused write's map inside a transaction" do
      {:ok, _entity} =
        Module19
        |> Entity.new(code: "nested_taken", slug: "nested_taken")
        |> create()

      result =
        transaction(fn ->
          Module19
          |> Entity.new(code: "nested_taken", slug: "nested_taken")
          |> create()
        end)

      assert result == {:ok, {:error, %{code: [:unique], slug: [:unique]}}}
    end

    test "returns a refused update's violations inside a transaction" do
      {:ok, first} =
        Module19
        |> Entity.new(slug: "nested_update_held")
        |> create()

      {:ok, second} =
        Module19
        |> Entity.new(slug: "nested_update_other")
        |> create()

      result =
        transaction(fn ->
          refusal = update(Module19, second.id, slug: first.slug)

          {refusal, update(Module19, second.id, slug: "nested_update_free")}
        end)

      assert result == {:ok, {{:error, %{slug: [:unique]}}, :ok}}
    end

    test "returns a refused write's violations inside a transaction and keeps it usable" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "nested_held")
        |> create()

      result =
        transaction(fn ->
          refusal =
            Module19
            |> Entity.new(slug: "nested_held")
            |> create()

          {:ok, other} =
            Module19
            |> Entity.new(slug: "nested_other")
            |> create()

          {refusal, other.id}
        end)

      assert {:ok, {{:error, %{slug: [:unique]}}, other_id}} = result
      assert read(Module19, other_id)
    end

    test "returns a restricted delete's referencer inside a transaction" do
      {:ok, target} =
        Module1
        |> Entity.new()
        |> create()

      {:ok, _referencing} =
        Module3
        |> Entity.new(c_id: target.id)
        |> create()

      result =
        transaction(fn ->
          refusal = delete(Module1, target.id)

          {refusal, read(Module1, target.id)}
        end)

      assert result == {:ok, {{:error, %{referenced_by: Module3, relationship: :c}}, target}}
    end

    test "returns a value violation inside a transaction" do
      result =
        transaction(fn ->
          Module2
          |> Entity.new(b: "nope")
          |> create()
        end)

      assert result == {:ok, {:error, %{b: [type: :integer], c: [:required]}}}
    end

    test "raises through the bang for a value violation inside a transaction" do
      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module2:
          * attribute :b must be of type :integer, got: "nope"
          * attribute :c is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        transaction(fn ->
          Module2
          |> Entity.new(b: "nope")
          |> create!()
        end)
      end
    end

    test "raises through the bang inside a transaction and rolls it back" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "nested_bang_held")
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :slug "nested_bang_held" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        transaction(fn ->
          {:ok, earlier} =
            Module19
            |> Entity.new(slug: "nested_bang_earlier")
            |> create()

          Process.put(:earlier_id, earlier.id)

          Module19
          |> Entity.new(slug: "nested_bang_held")
          |> create!()
        end)
      end

      assert read(Module19, Process.get(:earlier_id)) == nil
    end
  end

  describe "update/3" do
    test "returns the unique violation from the write itself" do
      {:ok, first} =
        Module19
        |> Entity.new(slug: "held")
        |> create()

      {:ok, second} =
        Module19
        |> Entity.new(slug: "other")
        |> create()

      assert update(Module19, second.id, slug: first.slug) == {:error, %{slug: [:unique]}}
    end

    test "returns a value violation and a taken unique value in one map" do
      {:ok, first} =
        Module19
        |> Entity.new(code: "gateway_update_taken", slug: "gateway_update_a")
        |> create()

      {:ok, second} =
        Module19
        |> Entity.new(code: "gateway_update_free", slug: "gateway_update_b")
        |> create()

      assert update(Module19, second.id, %{code: first.code, slug: 123}) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    test "returns a missing reference target" do
      {:ok, target_entity} =
        Module1
        |> Entity.new()
        |> create()

      {:ok, entity} =
        Module3
        |> Entity.new(c_id: target_entity.id)
        |> create()

      assert update(Module3, entity.id, %{c_id: Entity.generate_id()}) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "returns every missing reference target" do
      {:ok, target_entity} =
        Module1
        |> Entity.new()
        |> create()

      {:ok, entity} =
        Module3
        |> Entity.new(c_id: target_entity.id)
        |> create()

      changes = %{b_id: Entity.generate_id(), c_id: Entity.generate_id()}

      assert update(Module3, entity.id, changes) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        update(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f", role: :owner)
      end
    end
  end

  describe "update!/1" do
    test "writes the changes recorded on the struct" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "before")
        |> create()

      assert entity
             |> put_attribute(:c, "after")
             |> update!() == :ok

      assert read(Module2, entity.id).c == "after"
    end

    test "lets a denied claim propagate" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "before")
        |> create()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Entity.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn ->
          entity
          |> put_attribute(:c, "after")
          |> update!()
        end)
      end

      assert read(Module2, entity.id).c == "before"
    end

    test "raises on a refused value" do
      {:ok, entity} =
        Module19
        |> Entity.new(slug: "taken")
        |> create()

      {:ok, other_entity} =
        Module19
        |> Entity.new(slug: "free")
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "taken" is already taken|

      assert_error WriteError, expected_msg, fn ->
        other_entity
        |> put_attribute(:slug, "taken")
        |> update!()
      end

      assert read(Module19, entity.id).slug == "taken"
    end

    test "raises naming a moved attribute's refused result" do
      {:ok, entity} =
        Module10
        |> Entity.new(count: 1)
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module10 #{inspect(entity.id)}:\n" <>
          "  * attribute :count must be at least 1"

      assert_error WriteError, expected_msg, fn ->
        entity
        |> decrement(:count, 1)
        |> update!()
      end

      assert read(Module10, entity.id).count == 1
    end

    test "names the value the write used, not the one the struct holds" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "written")
        |> create()

      {:ok, other_entity} =
        Module19
        |> Entity.new(slug: "spare")
        |> create()

      # The recorded change is what the write uses - a field set directly on the struct
      # afterwards is neither written nor named in the refusal.
      entity = %{put_attribute(other_entity, :slug, "written") | slug: "set directly"}

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "written" is already taken|

      assert_error WriteError, expected_msg, fn -> update!(entity) end
    end

    test "raises on a refused value inside a transaction" do
      {:ok, _entity} =
        Module19
        |> Entity.new(slug: "held")
        |> create()

      {:ok, other_entity} =
        Module19
        |> Entity.new(slug: "spare")
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "held" is already taken|

      assert_error WriteError, expected_msg, fn ->
        transaction(fn ->
          other_entity
          |> put_attribute(:slug, "held")
          |> update!()
        end)
      end
    end
  end

  describe "update!/3" do
    test "returns :ok" do
      {:ok, entity} =
        Module19
        |> Entity.new(slug: "before")
        |> create()

      assert update!(Module19, entity.id, slug: "after") == :ok
    end

    test "raises a write error naming every change violation" do
      {:ok, entity} =
        Module2
        |> Entity.new(a: true, c: "some text")
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module2 "#{entity.id}":
          * attribute :b must be of type :integer, got: "nope"\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module2, entity.id, b: "nope")
      end

      error =
        try do
          update!(Module2, entity.id, b: "nope")
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{b: [type: :integer]}
    end

    test "raises a write error when the new value is taken" do
      {:ok, first} =
        Module19
        |> Entity.new(slug: "held")
        |> create()

      {:ok, second} =
        Module19
        |> Entity.new(slug: "other")
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module19 "#{second.id}":
          * attribute :slug "held" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module19, second.id, slug: first.slug)
      end

      error =
        try do
          update!(Module19, second.id, slug: first.slug)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{slug: [:unique]}
    end

    test "raises naming the missing target" do
      gone_id = Entity.generate_id()

      {:ok, target_entity} =
        Module1
        |> Entity.new()
        |> create()

      {:ok, entity} =
        Module3
        |> Entity.new(c_id: target_entity.id)
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module3 "#{entity.id}":
          * reference :c_id "#{gone_id}" names no existing entity\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module3, entity.id, c_id: gone_id)
      end

      error =
        try do
          update!(Module3, entity.id, c_id: gone_id)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{c_id: [:not_found]}
    end
  end

  describe "update/1" do
    test "writes the changes recorded on the struct" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "before")
        |> create()

      assert entity
             |> put_attribute(:c, "after")
             |> update() == :ok

      assert read(Module2, entity.id).c == "after"
    end

    test "raises a teaching error for a struct carrying nothing recorded" do
      {:ok, entity} = create(Entity.new(Module1))

      expected_msg =
        "update takes recorded changes - put values with put_attribute, move counters with " <>
          "increment or decrement, and edges with add_relationship or delete_relationship. " <>
          "A field set directly on the struct is not recorded: writing the whole struct " <>
          "would overwrite concurrent changes to fields you didn't touch."

      assert_error ArgumentError, expected_msg, fn -> update(entity) end
    end
  end
end
