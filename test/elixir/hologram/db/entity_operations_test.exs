defmodule Hologram.DB.EntityOperationsTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.EntityOperations

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Clock
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module20
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Role

  defp count_edges(source_entity, target_entity) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module3_a_$join" WHERE "source_id" = $1 AND "target_id" = $2|

    encoded_source_id = Codec.encode(source_entity.id, :uuid)
    encoded_target_id = Codec.encode(target_entity.id, :uuid)

    {:ok, %Postgrex.Result{rows: [[count]]}} =
      Connection.query(count_sql, [encoded_source_id, encoded_target_id])

    count
  end

  defp oplog_effects do
    statement = """
    SELECT "op", "type", "entity_id", "data", "revisions"
    FROM "hologram_system"."oplog"
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [op, type, entity_id, data, revisions] ->
      %{
        data: data,
        entity_id: Codec.decode(entity_id, :uuid),
        op: op,
        revisions: revisions,
        type: type
      }
    end)
  end

  # The system clock can be coarser than a microsecond (Windows timer granularity reaches
  # ~16ms), making consecutive utc_now readings equal - wait until the clock has visibly
  # advanced, so that a subsequent write provably stamps a later timestamp.
  # The lock modes this session holds on the entity type's table - a FOR UPDATE read holds
  # RowShareLock on the relation, a plain read only AccessShareLock.
  defp relation_lock_modes(entity_type) do
    statement =
      "SELECT mode FROM pg_locks WHERE relation = $1::text::regclass AND pid = pg_backend_pid()"

    relation = ~s|"hologram_data"."#{Mapper.table_name(entity_type)}"|

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [relation])

    Enum.map(rows, fn [mode] -> mode end)
  end

  # Both timestamp columns are written from a stamp, which holds milliseconds - so waiting for the
  # wall clock to pass a microsecond of the same millisecond proves nothing: the next write would
  # land on the very same value. What has to move is the millisecond.
  defp wait_until_clock_advances_past(datetime) do
    now = DateTime.utc_now(:millisecond)

    if DateTime.compare(now, datetime) == :gt do
      :ok
    else
      Process.sleep(1)
      wait_until_clock_advances_past(datetime)
    end
  end

  describe "add_relationship/4" do
    test "adds an edge to the join table" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      assert add_relationship(Module3, source_entity.id, :a, target_entity.id) == :ok

      assert count_edges(source_entity, target_entity) == 1
    end

    test "is idempotent" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)
      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert count_edges(source_entity, target_entity) == 1
    end

    test "records the edge it added" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert effect = List.last(oplog_effects())
      assert effect.op == "add_relationship"
      assert effect.type == "Hologram.Test.Fixtures.Entity.Module3"
      assert effect.entity_id == source_entity.id
      assert effect.data == %{"relationship" => "a", "target_id" => target_entity.id}
    end

    test "records nothing when the edge is already there" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)
      effects_after_first = oplog_effects()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert oplog_effects() == effects_after_first
    end

    test "raises when the relationship is not a declared to-many relationship" do
      expected_msg =
        "invalid relationship for Hologram.Test.Fixtures.Entity.Module3 - :b is not a declared to-many relationship"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(Module3, Entity.generate_id(), :b, Entity.generate_id())
      end
    end

    test "raises when the source or target entity is missing" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      error =
        try do
          add_relationship(Module3, source_entity.id, :a, Entity.generate_id())
        rescue
          error in Postgrex.Error -> error
        end

      assert error.postgres.code == :foreign_key_violation
    end
  end

  describe "create/1" do
    test "inserts a full row and stamps both timestamps with the same value" do
      entity = Module2.new(a: true, c: "some text")

      {:ok, created_entity} = create(entity)

      assert %DateTime{} = created_entity.created_at
      assert created_entity.updated_at == created_entity.created_at

      select_sql =
        ~s|SELECT "a", "b", "c" FROM "hologram_data"."test_fixtures_entity_module2" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[true, nil, "some text"]]}} =
               Connection.query(select_sql, [encoded_id])
    end

    test "encodes attribute values per type at the driver boundary" do
      written_at = DateTime.utc_now(:microsecond)

      entity = Module4.new(a: ~D[2026-07-19], b: written_at, d: 1.5)

      {:ok, created_entity} = create(entity)

      select_sql =
        ~s|SELECT "a", "b", "c", "d" FROM "hologram_data"."test_fixtures_entity_module4" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[~D[2026-07-19], ^written_at, "x", 1.5]]}} =
               Connection.query(select_sql, [encoded_id])
    end

    test "writes to-one relationship references into the reference columns" do
      {:ok, target_entity} = create(Module1.new())

      entity = Module3.new(c_id: target_entity.id)

      {:ok, created_entity} = create(entity)

      select_sql =
        ~s|SELECT "b_id", "c_id" FROM "hologram_data"."test_fixtures_entity_module3" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)
      encoded_target_id = Codec.encode(target_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[nil, ^encoded_target_id]]}} =
               Connection.query(select_sql, [encoded_id])
    end

    test "records the insert as an effect carrying the whole entity" do
      entity = Module2.new(a: true, c: "some text")

      {:ok, created_entity} = create(entity)

      assert [effect] = oplog_effects()
      assert effect.op == "put_entity"
      assert effect.type == "Hologram.Test.Fixtures.Entity.Module2"
      assert effect.entity_id == created_entity.id

      assert effect.data == %{
               "a" => true,
               "b" => nil,
               "c" => "some text",
               "created_at" => DateTime.to_iso8601(created_entity.created_at),
               "id" => created_entity.id,
               "updated_at" => DateTime.to_iso8601(created_entity.updated_at)
             }
    end

    test "records the creator's grants after the entity they are granted on" do
      {:ok, user} =
        %{email: "creator@example.com"}
        |> Module14.new()
        |> create()

      {:ok, created_entity} =
        Context.with_actor(user.id, fn ->
          create(PolicyModule1.new())
        end)

      effects = oplog_effects()

      assert [_user, entity_effect | grant_effects] = effects
      assert entity_effect.entity_id == created_entity.id

      assert Enum.map(grant_effects, & &1.type) == [
               "Hologram.Auth.RoleGrant",
               "Hologram.Auth.RoleGrant"
             ]

      assert Enum.map(grant_effects, &Map.fetch!(&1.data, "role")) == ["maintainer", "owner"]
    end

    test "stamps every settable column with the insert's stamp" do
      {:ok, required_target} = create(Module1.new())

      {:ok, optional_target} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      {:ok, created_entity} =
        %{b_id: optional_target.id, c_id: required_target.id}
        |> Module3.new()
        |> create()

      revisions = created_entity.__meta__.revisions

      # Module3 declares no attributes and one to-many, which derives no column - so its settable
      # set is exactly its two to-one reference columns.
      stamped_fields =
        revisions
        |> Map.keys()
        |> Enum.sort()

      distinct_stamps =
        revisions
        |> Map.values()
        |> Enum.uniq()

      assert stamped_fields == [:b_id, :c_id]
      assert length(distinct_stamps) == 1
    end

    test "stores a stamp the struct carries as every column's revision" do
      # Far past anything this node's clock would answer, so a stamp taken here rather than given
      # cannot coincide with it.
      stamp = 4_000_000_000_000_000

      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> Map.put(:__meta__, %Metadata{stamp: stamp})
        |> create()

      reloaded_entity = get(Module2, created_entity.id)

      assert created_entity.__meta__.revisions == %{a: stamp, b: stamp, c: stamp}
      assert reloaded_entity.__meta__.revisions == %{a: stamp, b: stamp, c: stamp}
    end

    test "stamps the row from the moment its writer made it" do
      # Months before this node's clock would answer - which is what a row written offline and
      # synced later carries. The moment it arrived is not the moment it was made.
      written_at = ~U[2026-01-15 10:30:00.000000Z]
      stamp = DateTime.to_unix(written_at, :millisecond) * 1024

      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> Map.put(:__meta__, %Metadata{stamp: stamp})
        |> create()

      assert created_entity.created_at == written_at
      assert created_entity.updated_at == written_at
      assert get(Module2, created_entity.id).created_at == written_at
    end

    # Bracketed against the CLOCK THE WRITE ITSELF READS, not against DateTime.utc_now/0. Two
    # reasons, and each one alone is enough: Windows ticks its wall clock about every 16 ms, so a
    # row created between two reads of it carries the same instant as both - and a stamp taken
    # after 1024 stamps in one millisecond runs a millisecond AHEAD of os_time, so an upper bound
    # read from outside the clock is not safe either. Between two stamps it is exact on every
    # platform, because the counter only moves forward.
    test "stamps the row from this node's clock when its writer authored none" do
      before_ms = Clock.wall_clock_ms(Clock.stamp())

      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      after_ms = Clock.wall_clock_ms(Clock.stamp())

      assert DateTime.to_unix(created_entity.created_at, :millisecond) in before_ms..after_ms
    end

    test "answers a struct carrying nothing of the write it made" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> Map.put(:__meta__, %Metadata{claim: :trust, stamp: 4_000_000_000_000_000})
        |> create()

      assert created_entity.__meta__.claim == nil
      assert created_entity.__meta__.stamp == nil
    end

    test "records the revisions on the effect" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      stamp = created_entity.__meta__.revisions.a

      assert [effect] = oplog_effects()
      assert effect.revisions == %{"a" => stamp, "b" => stamp, "c" => stamp}
    end

    test "reloads with the revisions it answered" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      reloaded_entity = get(Module2, created_entity.id)

      assert reloaded_entity.__meta__.revisions == created_entity.__meta__.revisions
    end

    test "returns the violation from the write itself when a unique attribute's value is taken" do
      {:ok, _entity} =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      result =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      assert result == {:error, %{slug: [:unique]}}
    end

    # Uniqueness is over the values an attribute holds, and nil is the absence of one.
    test "admits any number of nils in an optional unique attribute" do
      assert {:ok, _first} =
               %{code: nil, slug: "a"}
               |> Module19.new()
               |> create()

      assert {:ok, _second} =
               %{code: nil, slug: "b"}
               |> Module19.new()
               |> create()
    end

    test "writes nothing and records nothing for a conflicting insert" do
      {:ok, entity} =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      result =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      assert result == {:error, %{slug: [:unique]}}
      assert Enum.map(oplog_effects(), & &1.entity_id) == [entity.id]
    end

    test "returns every value violation without writing a row" do
      entity = Module2.new(b: "nope")

      assert create(entity) == {:error, %{b: [type: :integer], c: [:required]}}
      assert get(Module2, entity.id) == nil
      assert oplog_effects() == []
    end

    test "returns declared constraint option violations" do
      assert create(Module10.new(count: 0)) == {:error, %{count: [min: 1]}}
    end

    # One byte over what the unique index's btree entry carries - refused here, before the insert,
    # so PostgreSQL never gets to raise program_limit_exceeded for it.
    test "returns the byte-bound violation for a unique string its index cannot carry" do
      entity = Module19.new(slug: String.duplicate("a", 2693))

      assert create(entity) == {:error, %{slug: [max_bytes: 2692]}}
    end

    test "returns reference violations" do
      assert create(Module3.new()) == {:error, %{c_id: [:required]}}

      assert create(Module3.new(c_id: "garbage")) == {:error, %{c_id: [type: :uuid]}}
    end

    # A well-formed id naming no row is a valid value, so it passes the declarations and the
    # write is the first thing that can know - the foreign key names the column back.
    test "returns a missing reference target from the write itself" do
      assert create(Module3.new(c_id: Entity.generate_id())) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "writes nothing and records nothing for a refused reference" do
      entity = Module3.new(c_id: Entity.generate_id())

      assert create(entity) == {:error, %{c_id: [:not_found]}}
      assert get(Module3, entity.id) == nil
      assert oplog_effects() == []
    end

    # PostgreSQL enforces foreign keys by triggers after the row goes in and abandons the
    # statement at the first one that fails, so the second missing target is never its to
    # report - it is asked about after the write, the way a second taken value is.
    test "reports every missing reference target" do
      assert create(Module3.new(b_id: Entity.generate_id(), c_id: Entity.generate_id())) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    # The values failed, so no write was attempted and nothing authoritative was learned - the
    # reference is asked about all the same, and one submit answers for both.
    test "reports a missing reference target beside a value violation" do
      gone_id = Entity.generate_id()

      assert create(Module13.new(parent_id: gone_id, title: nil)) ==
               {:error, %{parent_id: [:not_found], title: [:required]}}
    end

    # A cleared reference names nothing to look for, and an optional one is free to stay empty.
    test "skips a nil reference" do
      assert create(Module13.new(parent_id: nil, title: nil)) ==
               {:error, %{title: [:required]}}
    end

    # A value that is not an id cannot be bound to the existence query at all, so the field keeps
    # the violation it earned - and the reference beside it is still asked about.
    test "skips a reference carrying its own violation" do
      assert create(Module3.new(b_id: Entity.generate_id(), c_id: "garbage")) ==
               {:error, %{b_id: [:not_found], c_id: [type: :uuid]}}
    end

    test "reports a value violation and a taken unique value together" do
      {:ok, _entity} =
        %{code: "taken", slug: "a"}
        |> Module19.new()
        |> create()

      assert create(Module19.new(code: "taken", slug: 123)) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    # PostgreSQL abandons the statement at the first constraint it refuses, so the second taken
    # value is never its to report - it is asked about after the write, the way it would be had
    # the values failed and no write been attempted at all.
    test "reports a second taken unique value the write did not reach" do
      {:ok, _entity} =
        %{code: "both_code", slug: "both_slug"}
        |> Module19.new()
        |> create()

      assert create(Module19.new(code: "both_code", slug: "both_slug")) ==
               {:error, %{code: [:unique], slug: [:unique]}}
    end

    # A value that is not even the right type cannot be compared against what other rows hold,
    # so the field keeps the violation it earned and nothing is asked about it.
    test "skips the advisory check for a field carrying its own violation" do
      {:ok, _entity} =
        %{code: "held", slug: "b"}
        |> Module19.new()
        |> create()

      assert create(Module19.new(code: 456, slug: 123)) ==
               {:error, %{code: [type: :string], slug: [type: :string]}}
    end

    # An optional unique attribute admits any number of nils, so a nil is never taken.
    test "skips nil values" do
      {:ok, _entity} =
        %{code: nil, slug: "c"}
        |> Module19.new()
        |> create()

      assert create(Module19.new(code: nil, slug: 123)) ==
               {:error, %{slug: [type: :string]}}
    end

    test "raises on constraint violations" do
      entity = Module1.new()
      {:ok, _entity} = create(entity)

      error =
        try do
          {:ok, _entity} = create(entity)
        rescue
          error in Postgrex.Error -> error
        end

      assert error.postgres.code == :unique_violation
    end
  end

  describe "create/1 creator grants" do
    defp granted_roles(user_id, entity_id) do
      select_sql =
        ~s|SELECT "role" FROM "hologram_data"."hologram_role_grant" | <>
          ~s|WHERE "user_id" = $1 AND "entity_id" = $2 ORDER BY "role"|

      params = [Codec.encode(user_id, :uuid), Codec.encode(entity_id, :uuid)]
      {:ok, %{rows: rows}} = Connection.query(select_sql, params)

      Enum.map(rows, fn [role] -> role end)
    end

    test "grants every creator role of the entity type to the acting user" do
      {:ok, user} =
        %{email: "user_3@example.com"}
        |> Module14.new()
        |> create()

      {:ok, resource} =
        Context.with_actor(user.id, fn ->
          create(PolicyModule1.new())
        end)

      assert granted_roles(user.id, resource.id) == ["maintainer", "owner"]
    end

    # The creator's grants are the one place the store is written outside the grant verbs, so
    # they derive their ids the same way - or a later grant of the same role from a browser
    # would carry a second id for one fact.
    test "mints each creator grant's id from the grant" do
      {:ok, user} =
        %{email: "user_5@example.com"}
        |> Module14.new()
        |> create()

      {:ok, resource} =
        Context.with_actor(user.id, fn ->
          create(PolicyModule1.new())
        end)

      select_sql =
        ~s|SELECT "role", "id" FROM "hologram_data"."hologram_role_grant" | <>
          ~s|WHERE "user_id" = $1 ORDER BY "role"|

      {:ok, %{rows: rows}} = Connection.query(select_sql, [Codec.encode(user.id, :uuid)])
      granted = Enum.map(rows, fn [role, id] -> {role, Codec.decode(id, :uuid)} end)

      entity_type = PolicyModule1

      assert granted == [
               {"maintainer",
                RoleGrant.derive_id(user.id, entity_type, resource.id, :maintainer)},
               {"owner", RoleGrant.derive_id(user.id, entity_type, resource.id, :owner)}
             ]
    end

    test "grants nothing outside an actor context" do
      {:ok, resource} = create(PolicyModule1.new())

      select_sql =
        ~s|SELECT count(*) FROM "hologram_data"."hologram_role_grant" WHERE "entity_id" = $1|

      {:ok, %{rows: [[count]]}} =
        Connection.query(select_sql, [Codec.encode(resource.id, :uuid)])

      assert count == 0
    end

    test "grants nothing for an entity type declaring no creator role" do
      {:ok, user} =
        %{email: "user_4@example.com"}
        |> Module14.new()
        |> create()

      {:ok, resource} =
        Context.with_actor(user.id, fn ->
          create(Module1.new())
        end)

      assert granted_roles(user.id, resource.id) == []
    end

    test "rolls the entity row back when a grant fails" do
      missing_user_id = Entity.generate_id()
      entity = PolicyModule1.new()

      assert_raise Postgrex.Error, fn ->
        Context.with_actor(missing_user_id, fn -> create(entity) end)
      end

      select_sql =
        ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_policy_module1" WHERE "id" = $1|

      {:ok, %{rows: [[count]]}} = Connection.query(select_sql, [Codec.encode(entity.id, :uuid)])

      assert count == 0
    end
  end

  describe "create_if_absent/1" do
    defp count_role_grants(user_id) do
      count_sql =
        ~s|SELECT count(*) FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|

      {:ok, %{rows: [[count]]}} = Connection.query(count_sql, [Codec.encode(user_id, :uuid)])

      count
    end

    defp role_grant(user, role) do
      %RoleGrant{id: Entity.generate_id(), role: role, user_id: user.id}
    end

    test "answers :created and inserts the entity when no conflicting row exists" do
      {:ok, user} =
        %{email: "user_1@example.com"}
        |> Module14.new()
        |> create()

      assert create_if_absent(role_grant(user, :owner)) == :created
      assert count_role_grants(user.id) == 1
    end

    test "answers :present and keeps the existing row when a unique index conflicts" do
      {:ok, user} =
        %{email: "user_2@example.com"}
        |> Module14.new()
        |> create()

      first_grant = role_grant(user, :owner)

      create_if_absent(first_grant)

      assert create_if_absent(role_grant(user, :owner)) == :present
      assert count_role_grants(user.id) == 1

      select_sql = ~s|SELECT "id" FROM "hologram_data"."hologram_role_grant" WHERE "user_id" = $1|
      {:ok, %{rows: [[id]]}} = Connection.query(select_sql, [Codec.encode(user.id, :uuid)])

      assert Codec.decode(id, :uuid) == first_grant.id
    end

    test "records the insert as an effect" do
      {:ok, user} =
        %{email: "user_3@example.com"}
        |> Module14.new()
        |> create()

      grant = role_grant(user, :owner)

      create_if_absent(grant)

      assert %{op: "put_entity", type: "Hologram.Auth.RoleGrant", entity_id: entity_id} =
               List.last(oplog_effects())

      assert entity_id == grant.id
    end

    test "records nothing when a conflicting row keeps the insert from happening" do
      {:ok, user} =
        %{email: "user_4@example.com"}
        |> Module14.new()
        |> create()

      create_if_absent(role_grant(user, :owner))
      effects_after_first = oplog_effects()

      create_if_absent(role_grant(user, :owner))

      assert oplog_effects() == effects_after_first
    end

    test "raises on an invalid entity" do
      grant = %RoleGrant{id: Entity.generate_id(), role: :owner}

      expected_msg =
        normalize_newlines("""
        invalid data for Hologram.Auth.RoleGrant:
          * reference :user_id is required\
        """)

      assert_error ArgumentError, expected_msg, fn -> create_if_absent(grant) end
    end

    # The framework's own grant rows are not a caller's to answer, so this path keeps raising
    # where create/1 explains - the constraint belongs to a type no caller named.
    test "raises when the grantee does not exist" do
      grant = %RoleGrant{id: Entity.generate_id(), role: :owner, user_id: Entity.generate_id()}

      error =
        try do
          create_if_absent(grant)
        rescue
          error in Postgrex.Error -> error
        end

      assert error.postgres.code == :foreign_key_violation
    end
  end

  describe "delete/2" do
    test "deletes the entity row" do
      {:ok, created_entity} = create(Module1.new())

      assert delete(Module1, created_entity.id) == :ok

      assert get(Module1, created_entity.id) == nil
    end

    test "deletes own outgoing edges with the row" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert delete(Module3, source_entity.id) == :ok

      assert get(Module3, source_entity.id) == nil
      assert count_edges(source_entity, target_entity) == 0
    end

    # A delete says what the row WAS, so the row stays readable in the log after it is gone.
    test "records the deletion, with the row it removed" do
      {:ok, created_entity} = create(Module1.new())

      delete(Module1, created_entity.id)

      assert effect = List.last(oplog_effects())
      assert effect.op == "del_entity"
      assert effect.type == "Hologram.Test.Fixtures.Entity.Module1"
      assert effect.entity_id == created_entity.id

      assert effect.data == %{
               "created_at" => DateTime.to_iso8601(created_entity.created_at),
               "id" => created_entity.id,
               "updated_at" => DateTime.to_iso8601(created_entity.updated_at)
             }
    end

    test "records nothing when no entity has the given id" do
      effects_before = oplog_effects()

      assert delete(Module1, Entity.generate_id()) == :ok

      assert oplog_effects() == effects_before
    end

    # The write and the record of it share a transaction, so a refusal takes both back.
    test "records nothing when the delete is restricted" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, _entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      effects_before = oplog_effects()

      assert {:error, %{referenced_by: _entity_type}} = delete(Module1, target_entity.id)

      assert oplog_effects() == effects_before
    end

    test "restricts when another entity references the entity" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, referencing_entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      assert delete(Module1, target_entity.id) ==
               {:error, %{referenced_by: Module3, relationship: :c}}

      assert get(Module1, target_entity.id) == target_entity
      assert get(Module3, referencing_entity.id) == referencing_entity
    end

    test "restricts when the entity is the target of another entity's edges" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert delete(Module2, target_entity.id) ==
               {:error, %{referenced_by: Module3, relationship: :a}}

      assert count_edges(source_entity, target_entity) == 1
    end

    # The grant store is an entity like any other, so its reference to the user is named the
    # same way. The grant is written with user_id alone - granted_by_id stays nil, so exactly
    # one foreign key references the user and the answer is deterministic.
    test "names the grant store when a grant still references the user" do
      {:ok, user} =
        %{email: "granted@example.com"}
        |> Module14.new()
        |> create()

      :ok = insert_global_grant(user.id, Role.Module1)

      assert delete(Module14, user.id) ==
               {:error, %{referenced_by: RoleGrant, relationship: :user}}
    end

    test "deleting a nonexistent id is a no-op" do
      assert delete(Module1, Entity.generate_id()) == :ok
    end
  end

  describe "delete_relationship/4" do
    test "deletes an edge from the join table" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert delete_relationship(Module3, source_entity.id, :a, target_entity.id) == :ok

      assert count_edges(source_entity, target_entity) == 0
    end

    test "deleting an absent edge is a no-op" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      assert delete_relationship(Module3, source_entity.id, :a, target_entity.id) == :ok
    end

    test "records the edge it removed" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      delete_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert effect = List.last(oplog_effects())
      assert effect.op == "del_relationship"
      assert effect.entity_id == source_entity.id
      assert effect.data == %{"relationship" => "a", "target_id" => target_entity.id}
    end

    test "records nothing when the edge was not there" do
      {:ok, required_target} = create(Module1.new())

      {:ok, source_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      {:ok, target_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      effects_before = oplog_effects()

      :ok = delete_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert oplog_effects() == effects_before
    end

    test "raises when the relationship is not a declared to-many relationship" do
      expected_msg =
        "invalid relationship for Hologram.Test.Fixtures.Entity.Module3 - :b is not a declared to-many relationship"

      assert_error ArgumentError, expected_msg, fn ->
        delete_relationship(Module3, Entity.generate_id(), :b, Entity.generate_id())
      end
    end
  end

  describe "get/3" do
    test "locks the row with lock: true" do
      {:ok, created_entity} = create(Module1.new())

      assert get(Module1, created_entity.id, lock: true) == created_entity
      assert "RowShareLock" in relation_lock_modes(Module1)
    end

    test "returns the entity with values decoded back into their logical types" do
      entity = Module4.new(a: ~D[2026-07-19], b: DateTime.utc_now(:microsecond), d: 1.5)

      {:ok, created_entity} = create(entity)

      assert get(Module4, created_entity.id) == created_entity
    end

    test "returns to-one relationship references as target ids" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, created_entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      assert get(Module3, created_entity.id) == created_entity
    end

    test "returns nil when no row matches" do
      assert get(Module1, Entity.generate_id()) == nil
    end

    test "takes no row lock without the option" do
      {:ok, created_entity} = create(Module1.new())

      get(Module1, created_entity.id)

      refute "RowShareLock" in relation_lock_modes(Module1)
    end

    test "fills the metadata with the row's revisions" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      set_revisions(Module2, created_entity.id, %{"a" => 3, "c" => 2})

      assert get(Module2, created_entity.id).__meta__.revisions == %{a: 3, c: 2}
    end

    test "reads a revisions entry naming no column as nothing" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      set_revisions(Module2, created_entity.id, %{"gone" => 1})

      assert get(Module2, created_entity.id).__meta__.revisions == %{}
    end
  end

  describe "update/4" do
    test "sets exactly the changed columns and bumps updated_at" do
      {:ok, created_entity} =
        %{a: true, b: 1, c: "before"}
        |> Module2.new()
        |> create()

      wait_until_clock_advances_past(created_entity.updated_at)

      assert update(Module2, created_entity.id, %{c: "after"}) == :ok

      reloaded_entity = get(Module2, created_entity.id)

      assert reloaded_entity.c == "after"
      assert reloaded_entity.a == created_entity.a
      assert reloaded_entity.b == created_entity.b
      assert reloaded_entity.created_at == created_entity.created_at
      assert DateTime.compare(reloaded_entity.updated_at, created_entity.updated_at) == :gt
    end

    test "stamps updated_at from the moment its writer made the change" do
      # The write was authored months ago and is only arriving now, so its stamp is below the
      # revision the row already holds - the revision advances past it, and updated_at still says
      # when the change was actually made.
      written_at = ~U[2026-01-15 10:30:00.000000Z]
      stamp = DateTime.to_unix(written_at, :millisecond) * 1024

      {:ok, created_entity} =
        %{a: true, c: "before"}
        |> Module2.new()
        |> create()

      assert update(Module2, created_entity.id, [c: "after"], stamp: stamp) == :ok

      assert get(Module2, created_entity.id).updated_at == written_at
    end

    test "records the changed attributes and the stamp they moved" do
      {:ok, created_entity} =
        %{a: true, b: 1, c: "before"}
        |> Module2.new()
        |> create()

      update(Module2, created_entity.id, %{c: "after"})

      reloaded_entity = get(Module2, created_entity.id)

      assert %{op: "patch_entity", type: "Hologram.Test.Fixtures.Entity.Module2"} =
               effect = List.last(oplog_effects())

      assert effect.entity_id == created_entity.id

      assert effect.data == %{
               "c" => "after",
               "updated_at" => DateTime.to_iso8601(reloaded_entity.updated_at)
             }
    end

    # The log records what a write did, whole - deciding what may be SHOWN is the wire's, against
    # the model of the moment, because server_only can be added to or removed from an attribute
    # long after the entry was written. wire_data_test.exs holds the twin proving the same value
    # never reaches a frame.
    test "records the value of a server-only attribute it changed" do
      {:ok, created_entity} =
        %{email: "before@example.com"}
        |> Module14.new()
        |> create()

      update(Module14, created_entity.id, %{password_hash: "hashed_secret_v2"})

      assert effect = List.last(oplog_effects())
      assert Map.keys(effect.data) == ["password_hash", "updated_at"]
      assert effect.data["password_hash"] == "hashed_secret_v2"
    end

    test "records nothing when no entity has the given id" do
      effects_before = oplog_effects()
      missing_id = Entity.generate_id()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module2 - no entity with id #{inspect(missing_id)}"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module2, missing_id, %{c: "after"})
      end

      assert oplog_effects() == effects_before
    end

    test "sets, reassigns and clears to-one references" do
      {:ok, first_target} = create(Module1.new())

      {:ok, second_target} = create(Module1.new())

      {:ok, optional_target} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      {:ok, created_entity} =
        %{c_id: first_target.id}
        |> Module3.new()
        |> create()

      :ok = update(Module3, created_entity.id, %{c_id: second_target.id})
      assert get(Module3, created_entity.id).c_id == second_target.id

      :ok = update(Module3, created_entity.id, %{b_id: optional_target.id})
      assert get(Module3, created_entity.id).b_id == optional_target.id

      :ok = update(Module3, created_entity.id, %{b_id: nil})
      assert get(Module3, created_entity.id).b_id == nil
    end

    test "raises the touched columns' revisions and leaves the rest" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      :ok = update(Module2, created_entity.id, a: false)

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert revisions.a > created_entity.__meta__.revisions.a
      assert revisions.c == created_entity.__meta__.revisions.c
    end

    test "records the revisions of the touched columns on the effect" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      :ok = update(Module2, created_entity.id, a: false)

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert %{revisions: effect_revisions} = List.last(oplog_effects())
      assert effect_revisions == %{"a" => revisions.a}
    end

    test "stamps every column of one update alike" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      :ok = update(Module2, created_entity.id, a: false, c: "xyz")

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert revisions.a > created_entity.__meta__.revisions.a
      assert revisions.c == revisions.a
    end

    test "never lowers a revision" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      # A revision a day ahead of this node's clock - what a peer whose clock runs fast, or a
      # client stamping its own write, can leave behind.
      ahead_of_this_node = (System.os_time(:millisecond) + 86_400_000) * 1024

      set_revisions(Module2, created_entity.id, %{"a" => ahead_of_this_node})

      :ok = update(Module2, created_entity.id, a: false)

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert revisions.a == ahead_of_this_node + 1
    end

    test "stores a given stamp as the revision of the columns it sets" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      stamp = created_entity.__meta__.revisions.a + 1_000_000

      :ok = update(Module2, created_entity.id, [a: false], stamp: stamp)

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert revisions.a == stamp
      assert revisions.c == created_entity.__meta__.revisions.c
    end

    test "never lowers a revision to a given stamp" do
      {:ok, created_entity} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      ahead = created_entity.__meta__.revisions.a + 1_000_000

      set_revisions(Module2, created_entity.id, %{"a" => ahead})

      :ok = update(Module2, created_entity.id, [a: false], stamp: ahead - 1)

      revisions = get(Module2, created_entity.id).__meta__.revisions

      assert revisions.a == ahead + 1
    end

    test "moves an integer attribute by a delta" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      assert update(Module10, created_entity.id, %{}, deltas: %{count: 3}) == :ok

      assert get(Module10, created_entity.id).count == 8
    end

    test "moves by a negative delta" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      :ok = update(Module10, created_entity.id, %{}, deltas: %{count: -2})

      assert get(Module10, created_entity.id).count == 3
    end

    test "moves a column beside one it sets" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      :ok = update(Module10, created_entity.id, %{bio: "moved"}, deltas: %{count: 1})

      updated_entity = get(Module10, created_entity.id)

      assert updated_entity.bio == "moved"
      assert updated_entity.count == 6
    end

    test "records the value a moved column ends at on the effect" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      :ok = update(Module10, created_entity.id, %{}, deltas: %{count: 3})

      assert [_put_effect, patch_effect] = oplog_effects()

      assert patch_effect.op == "patch_entity"
      assert patch_effect.data["count"] == 8
      assert Map.has_key?(patch_effect.data, "updated_at")
      assert Map.keys(patch_effect.revisions) == ["count"]
    end

    test "stamps a moved column" do
      {:ok, created_entity} =
        %{count: 5, priority: 1}
        |> Module10.new()
        |> create()

      :ok = update(Module10, created_entity.id, %{}, deltas: %{count: 3})

      revisions = get(Module10, created_entity.id).__meta__.revisions

      assert revisions.count > created_entity.__meta__.revisions.count
      assert revisions.priority == created_entity.__meta__.revisions.priority
    end

    test "refuses a result below the declared minimum" do
      {:ok, created_entity} =
        %{count: 1}
        |> Module10.new()
        |> create()

      assert update(Module10, created_entity.id, %{}, deltas: %{count: -1}) ==
               {:error, %{count: [{:min, 1}]}}

      assert get(Module10, created_entity.id).count == 1
    end

    test "refuses a result above the declared maximum" do
      {:ok, created_entity} =
        %{count: 10}
        |> Module10.new()
        |> create()

      assert update(Module10, created_entity.id, %{}, deltas: %{count: 1}) ==
               {:error, %{count: [{:max, 10}]}}
    end

    test "changes nothing and records nothing for a refused result" do
      {:ok, created_entity} =
        %{count: 1}
        |> Module10.new()
        |> create()

      {:error, _violations} =
        update(Module10, created_entity.id, %{bio: "kept out"}, deltas: %{count: -1})

      updated_entity = get(Module10, created_entity.id)

      assert updated_entity.bio == nil
      assert updated_entity.count == 1
      assert [%{op: "put_entity"}] = oplog_effects()
    end

    test "refuses a move past what the column can hold" do
      max_int = 9_223_372_036_854_775_807

      {:ok, created_entity} =
        %{count: max_int}
        |> Module20.new()
        |> create()

      assert update(Module20, created_entity.id, %{}, deltas: %{count: 1}) ==
               {:error, %{count: [{:type, :integer}]}}

      assert get(Module20, created_entity.id).count == max_int
    end

    test "names only the counter that moved past what its column can hold" do
      max_int = 9_223_372_036_854_775_807

      {:ok, created_entity} =
        %{count: 1, views: max_int}
        |> Module20.new()
        |> create()

      assert update(Module20, created_entity.id, %{}, deltas: %{count: 1, views: 1}) ==
               {:error, %{views: [{:type, :integer}]}}

      reloaded = get(Module20, created_entity.id)

      assert reloaded.count == 1
      assert reloaded.views == max_int
    end

    test "raises when a delta names anything but a required integer attribute" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      expected_msg =
        "invalid deltas for Hologram.Test.Fixtures.Entity.Module10 - only required integer attributes can be moved: :bio, :nope, :priority"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module10, created_entity.id, %{}, deltas: %{bio: 1, nope: 1, priority: 1})
      end
    end

    test "raises when a field is both changed and moved" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      expected_msg =
        "invalid deltas for Hologram.Test.Fixtures.Entity.Module10 - a field is either changed or moved, not both: :count"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module10, created_entity.id, %{count: 7}, deltas: %{count: 1})
      end
    end

    test "returns the violation from the write itself when the new value is taken" do
      {:ok, first} =
        %{slug: "taken"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{slug: "free"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, slug: first.slug) == {:error, %{slug: [:unique]}}
    end

    test "updates a unique attribute to a free value" do
      {:ok, entity} =
        %{slug: "before"}
        |> Module19.new()
        |> create()

      assert update(Module19, entity.id, slug: "after") == :ok
    end

    # A row is not its own duplicate - the index excludes it, and so must a resubmitted form
    # that changed nothing about the unique value.
    test "updates a unique attribute to its own current value" do
      {:ok, entity} =
        %{slug: "unchanged"}
        |> Module19.new()
        |> create()

      assert update(Module19, entity.id, slug: "unchanged") == :ok
    end

    test "records nothing for a conflicting update" do
      {:ok, first} =
        %{slug: "held"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{slug: "other"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, slug: first.slug) == {:error, %{slug: [:unique]}}

      assert Enum.map(oplog_effects(), & &1.op) == ["put_entity", "put_entity"]
    end

    test "reports a value violation and a taken unique value together" do
      {:ok, first} =
        %{code: "update_taken", slug: "update_a"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{code: "update_free", slug: "update_b"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, %{code: first.code, slug: 123}) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    test "reports a second taken unique value the write did not reach" do
      {:ok, first} =
        %{code: "upd_both_code", slug: "upd_both_slug"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{code: "upd_other_code", slug: "upd_other_slug"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, %{code: first.code, slug: first.slug}) ==
               {:error, %{code: [:unique], slug: [:unique]}}
    end

    # The unique index excludes the row from its own comparison, and so does the advisory
    # query - a resubmitted form carrying a row's unchanged value must not be refused.
    test "does not count the row's own value as taken" do
      {:ok, entity} =
        %{code: "update_own", slug: "update_c"}
        |> Module19.new()
        |> create()

      assert update(Module19, entity.id, %{code: entity.code, slug: 123}) ==
               {:error, %{slug: [type: :string]}}
    end

    test "returns every change violation without writing" do
      {:ok, created_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      assert update(Module2, created_entity.id, %{b: "nope", c: nil}) ==
               {:error, %{b: [type: :integer], c: [:required]}}

      assert get(Module2, created_entity.id).c == "some text"
    end

    test "returns declared constraint option violations" do
      {:ok, created_entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      assert update(Module10, created_entity.id, %{count: 0}) == {:error, %{count: [min: 1]}}
    end

    test "returns reference change violations" do
      {:ok, required_target} = create(Module1.new())

      {:ok, created_entity} =
        %{c_id: required_target.id}
        |> Module3.new()
        |> create()

      assert update(Module3, created_entity.id, %{c_id: nil}) == {:error, %{c_id: [:required]}}

      assert update(Module3, created_entity.id, %{c_id: "garbage"}) ==
               {:error, %{c_id: [type: :uuid]}}
    end

    test "returns a missing reference target from the write itself" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, created_entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      assert update(Module3, created_entity.id, %{c_id: Entity.generate_id()}) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "changes nothing and records nothing for a refused reference" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, created_entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      effects_before = oplog_effects()

      assert update(Module3, created_entity.id, %{c_id: Entity.generate_id()}) ==
               {:error, %{c_id: [:not_found]}}

      assert get(Module3, created_entity.id).c_id == target_entity.id
      assert oplog_effects() == effects_before
    end

    # The write names the first foreign key it refuses and abandons the rest, so the second
    # missing target is asked about after it - the create half's rule, on the update path.
    test "reports every missing reference target" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, created_entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      changes = %{b_id: Entity.generate_id(), c_id: Entity.generate_id()}

      assert update(Module3, created_entity.id, changes) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    test "reports a missing reference target beside a value violation" do
      {:ok, created_entity} =
        %{title: "some title"}
        |> Module13.new()
        |> create()

      changes = %{parent_id: Entity.generate_id(), title: nil}

      assert update(Module13, created_entity.id, changes) ==
               {:error, %{parent_id: [:not_found], title: [:required]}}
    end

    # An unchanged reference is absent from the changes, so nothing is asked about it. What
    # binds here is the nil filter alone: referential integrity keeps an unchanged reference
    # pointing at a live row, so asking about it would answer "exists" and add nothing - reading
    # the whole row instead of the changes was mutated in and every test still passed.
    test "asks only about changed references" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, created_entity} =
        %{parent_id: target_entity.id, title: "some title"}
        |> Module13.new()
        |> create()

      assert update(Module13, created_entity.id, %{title: nil}) == {:error, %{title: [:required]}}
    end

    test "raises when changes name anything but declared attributes and to-one relationships" do
      {:ok, created_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      expected_unknown_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module2 - only declared attributes and to-one relationships can be updated: :nonexistent"

      assert_error ArgumentError, expected_unknown_msg, fn ->
        update(Module2, created_entity.id, %{nonexistent: 1})
      end

      expected_system_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module2 - only declared attributes and to-one relationships can be updated: :created_at"

      assert_error ArgumentError, expected_system_msg, fn ->
        update(Module2, created_entity.id, %{created_at: DateTime.utc_now(:microsecond)})
      end

      expected_revisions_msg =
        ~s(invalid changes for Hologram.Test.Fixtures.Entity.Module2 - only declared attributes and to-one relationships can be updated: :"$revisions")

      assert_error ArgumentError, expected_revisions_msg, fn ->
        update(Module2, created_entity.id, %{"$revisions": %{}})
      end
    end

    test "raises when changes are empty" do
      {:ok, created_entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      expected_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module2 - at least one declared attribute or to-one relationship must be changed"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module2, created_entity.id, %{})
      end

      assert_error ArgumentError, expected_msg, fn ->
        update(Module2, created_entity.id, %{}, deltas: %{})
      end
    end

    test "raises when the id names no entity" do
      nonexistent_id = Entity.generate_id()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module2 - no entity with id #{inspect(nonexistent_id)}"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module2, nonexistent_id, %{c: "some text"})
      end
    end
  end
end
