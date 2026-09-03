defmodule Hologram.MutationTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Mutation

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.Compiler.Encoder
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Record
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module20
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  # A row whose author is the given user, which `allow :archive, author_id: user_id()` grants that
  # user - the fixtures' one write rule that needs no role grant and holds on a multi-column type.
  defp create_archivable(user, values) do
    values
    |> Keyword.put(:author_id, user.id)
    |> PolicyModule1.new()
    |> DB.create!()
  end

  # What a client holding this row would send as `based_on` - its whole revisions map, keyed the
  # way the wire keys it. A delete touches every column, so it carries all of them.
  defp based_on(row) do
    Map.new(row.__meta__.revisions, fn {name, revision} -> {Atom.to_string(name), revision} end)
  end

  defp count_edges(source_id, target_id) do
    statement =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module16_secrets_$join" | <>
        ~s|WHERE "source_id" = $1 AND "target_id" = $2|

    {:ok, %Postgrex.Result{rows: [[count]]}} =
      Connection.query(statement, [
        Codec.encode(source_id, :uuid),
        Codec.encode(target_id, :uuid)
      ])

    count
  end

  defp create_shared do
    DB.create!(PolicyModule2.new())
  end

  defp create_source do
    DB.create!(Module16.new())
  end

  defp create_target do
    %{token: "t"}
    |> Module15.new()
    |> DB.create!()
  end

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp create_write(entity_type, id, data, opts \\ []) do
    %{
      "op" => "create",
      "type" => inspect(entity_type),
      "id" => id,
      "data" => data,
      "claim" => Keyword.get(opts, :claim),
      "stamp" => Keyword.get(opts, :stamp, stamp())
    }
  end

  defp delete_write(entity_type, id, opts \\ []) do
    %{
      "op" => "delete",
      "type" => inspect(entity_type),
      "id" => id,
      "data" => Keyword.get(opts, :data),
      "based_on" => Keyword.get(opts, :based_on),
      "claim" => Keyword.get(opts, :claim),
      "stamp" => Keyword.get(opts, :stamp, stamp())
    }
  end

  defp edge_write(op, entity_type, id, relationship, target_id) do
    %{
      "op" => op,
      "type" => inspect(entity_type),
      "id" => id,
      "relationship" => relationship,
      "target_id" => target_id,
      # No fixture grants a write operation on a type that declares a to-many, and what is under
      # test here is that an edge reaches the executor - so the write claims an operation the
      # fixture DOES grant. `allow :read` is a bare rule, which grants it to anyone.
      "claim" => ["authorize", "read"]
    }
  end

  defp envelope(writes, opts \\ []) do
    %{
      "instance_id" => "i1",
      "replica_id" => Keyword.get(opts, :replica_id, Entity.generate_id()),
      "model_hash" => Keyword.get(opts, :model_hash, Model.hash()),
      "seq" => Keyword.get(opts, :seq, 1),
      "writes" => writes
    }
  end

  # Scoped to one batch by its own mutation_ref: the outbox is shared, and what these ask about is
  # the effects of the batch under test rather than everything the table happens to hold.
  defp outbox_rows(replica_id) do
    statement = """
    SELECT "type", "entity_id", "actor_id", "mutation_ref"
    FROM "hologram_system"."outbox"
    WHERE "mutation_ref"->>'replica_id' = $1
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id])

    Enum.map(rows, fn [type, entity_id, actor_id, mutation_ref] ->
      %{
        actor_id: Codec.decode(actor_id, :uuid),
        entity_id: Codec.decode(entity_id, :uuid),
        mutation_ref: mutation_ref,
        type: type
      }
    end)
  end

  defp grant_id(user_id, resource, role) do
    RoleGrant.derive_id(user_id, resource.__struct__, resource.id, role)
  end

  # A grant as a browser sends it: the id derived from the grant, no claim (the parser refuses
  # one), and a granter of the client's own choosing - which the server overwrites.
  defp grant_write(user_id, resource, role, opts \\ []) do
    entity_type = resource.__struct__

    data = %{
      "granted_by_id" => Keyword.get(opts, :granted_by_id, user_id),
      "entity_id" => resource.id,
      "entity_type" => Codec.encode_enum_value(entity_type),
      "role" => Atom.to_string(role),
      "user_id" => user_id
    }

    id = RoleGrant.derive_id(user_id, entity_type, resource.id, role)

    create_write(RoleGrant, id, data, Keyword.delete(opts, :granted_by_id))
  end

  defp publish_write(id, opts \\ []) do
    claim_opts = Keyword.merge([claim: ["authorize", "publish"]], opts)

    create_write(PolicyModule2, id, %{"public" => true}, claim_opts)
  end

  # The fixtures declaring constraints, unique values and references grant no WRITE operation, so
  # these writes claim :read - a bare `allow :read` grants it to anyone, and what is under test is
  # the value the write carries rather than the claim it makes.
  # A revocation as a browser sends it: the grant it revokes, under the id derived from it.
  defp revocation_write(user_id, resource, role, opts \\ []) do
    entity_type = resource.__struct__

    data = %{
      "entity_id" => resource.id,
      "entity_type" => Codec.encode_enum_value(entity_type),
      "role" => Atom.to_string(role),
      "user_id" => user_id
    }

    id = RoleGrant.derive_id(user_id, entity_type, resource.id, role)

    delete_write(RoleGrant, id, Keyword.put(opts, :data, data))
  end

  defp readable_write(entity_type, id, data) do
    create_write(entity_type, id, data, claim: ["authorize", "read"])
  end

  # The batch the record kept for a refusal, or nil when it kept none.
  defp record_envelope(replica_id, seq) do
    statement = """
    SELECT "envelope" FROM "hologram_system"."mutation"
    WHERE "replica_id" = $1 AND "seq" = $2
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id, seq])

    case rows do
      [[envelope]] -> envelope
      [] -> nil
    end
  end

  # What a refusal answers, spelled as the wire carries it.
  defp rejected(index, reason) do
    {:ok,
     %{
       "reason" => Encoder.encode_client_term!(reason),
       "status" => "rejected",
       "write" => index
     }}
  end

  defp server(user_id \\ nil), do: %Server{user_id: user_id}

  defp update_write(entity_type, id, data, opts \\ []) do
    base = %{
      "op" => "update",
      "type" => inspect(entity_type),
      "id" => id,
      "based_on" => Keyword.get(opts, :based_on),
      "claim" => Keyword.get(opts, :claim, ["authorize", "archive"]),
      "stamp" => Keyword.get(opts, :stamp, stamp())
    }

    with_data = if data, do: Map.put(base, "data", data), else: base

    case Keyword.get(opts, :deltas) do
      nil -> with_data
      deltas -> Map.put(with_data, "deltas", deltas)
    end
  end

  # A counter row anyone may update - Module20's allow lines are bare, so its writes are granted
  # with or without an actor, which is what a delta test needs and no other fixture offers.
  defp create_counter(count) do
    %{count: count}
    |> Module20.new()
    |> DB.create!()
  end

  # A stamp from the wall clock, for a write against a row this test did NOT just create. For one
  # that did, use stamp_above/1: this node's clock can already be ahead of raw os_time, so a
  # wall-clock stamp can sit BELOW the revisions of a row written moments ago - and the merge
  # compares against those whether or not the write carries a based_on.
  defp stamp, do: System.os_time(:millisecond) * 1024

  # A stamp above every revision the row holds. The wall clock alone will not do: this node's
  # clock is `max(last + 1, os_time * 1024)`, so a row written in this millisecond can already
  # carry a revision ABOVE raw os_time - and the applier refuses a stamp that is not above the
  # revisions its own write says it was based on.
  defp stamp_above(row) do
    highest =
      row.__meta__.revisions
      |> Map.values()
      |> Enum.max()

    max(stamp(), highest + 1)
  end

  describe "run/2" do
    test "applies a create and answers confirmed" do
      id = Entity.generate_id()

      assert run(envelope([publish_write(id)]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(PolicyModule2, id).public == true
    end

    test "applies every write of a batch" do
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      writes = [publish_write(first_id), publish_write(second_id)]

      assert {:ok, %{"status" => "confirmed"}} = run(envelope(writes), server())

      assert EntityOperations.get(PolicyModule2, first_id) != nil
      assert EntityOperations.get(PolicyModule2, second_id) != nil
    end

    test "stores the writer's stamp as every column's revision" do
      id = Entity.generate_id()
      writer_stamp = stamp()

      run(envelope([publish_write(id, stamp: writer_stamp)]), server())

      assert EntityOperations.get(PolicyModule2, id).__meta__.revisions == %{public: writer_stamp}
    end

    test "records the batch on the effect it wrote" do
      id = Entity.generate_id()
      replica_id = Entity.generate_id()

      run(envelope([publish_write(id)], replica_id: replica_id, seq: 7), server())

      assert [%{entity_id: ^id, mutation_ref: %{"replica_id" => ^replica_id, "seq" => 7}}] =
               outbox_rows(replica_id)
    end

    test "records the acting user on the effect" do
      user = create_user("publisher@example.com")
      id = Entity.generate_id()
      replica_id = Entity.generate_id()

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([publish_write(id)], replica_id: replica_id), server(user.id))

      assert [%{actor_id: actor_id}] = outbox_rows(replica_id)
      assert actor_id == user.id
    end

    test "records the applied batch" do
      replica_id = Entity.generate_id()

      run(
        envelope([publish_write(Entity.generate_id())], replica_id: replica_id, seq: 3),
        server()
      )

      assert Record.find(replica_id, 3).result ==
               %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}
    end

    test "answers a repeated batch from the record without applying it again" do
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"} = answer} = run(batch, server())
      assert run(batch, server()) == {:ok, answer}

      assert length(outbox_rows(batch["replica_id"])) == 1
    end

    test "applies each sequence number of one replica on its own" do
      replica_id = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([publish_write(first_id)], replica_id: replica_id, seq: 1), server())
      run(envelope([publish_write(second_id)], replica_id: replica_id, seq: 2), server())

      assert EntityOperations.get(PolicyModule2, first_id) != nil
      assert EntityOperations.get(PolicyModule2, second_id) != nil

      assert Record.find(replica_id, 1) != nil
      assert Record.find(replica_id, 2) != nil
    end

    test "applies one sequence number for each replica on its own" do
      first_client = Entity.generate_id()
      second_client = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([publish_write(first_id)], replica_id: first_client, seq: 1), server())
      run(envelope([publish_write(second_id)], replica_id: second_client, seq: 1), server())

      assert EntityOperations.get(PolicyModule2, first_id) != nil
      assert EntityOperations.get(PolicyModule2, second_id) != nil

      assert Record.find(first_client, 1) != nil
      assert Record.find(second_client, 1) != nil
    end

    test "applies an update to the columns the writer saw unchanged" do
      user = create_user("author@example.com")
      row = create_archivable(user, priority: 5)
      writer_stamp = row.__meta__.revisions.priority + 1_000_000

      write =
        update_write(PolicyModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: writer_stamp
        )

      assert run(envelope([write]), server(user.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      reloaded = EntityOperations.get(PolicyModule1, row.id)

      assert reloaded.priority == 9
      assert reloaded.__meta__.revisions.priority == writer_stamp
      assert reloaded.__meta__.revisions.public == row.__meta__.revisions.public
    end

    test "drops a column the row holds a newer revision of, naming what lost and what stands" do
      user = create_user("outrun@example.com")
      row = create_archivable(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(PolicyModule1, row.id, %{"priority" => newer})

      write =
        update_write(PolicyModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, answer} = run(envelope([write]), server(user.id))

      assert answer["dropped"] == %{"0" => %{"priority" => 9}}

      # What WON, so a client can show it the moment the answer lands rather than waiting for the
      # frame that carries it.
      assert answer["kept"]["0"]["priority"] == 5
      assert answer["kept"]["0"]["$revisions"]["priority"] == newer

      assert EntityOperations.get(PolicyModule1, row.id).priority == 5
    end

    test "applies the rest of an update whose column was dropped" do
      user = create_user("partial@example.com")
      row = create_archivable(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(PolicyModule1, row.id, %{"priority" => newer})

      write =
        update_write(PolicyModule1, row.id, %{"priority" => 9, "public" => true},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, %{"dropped" => %{"0" => %{"priority" => 9}}}} =
               run(envelope([write]), server(user.id))

      reloaded = EntityOperations.get(PolicyModule1, row.id)

      assert reloaded.priority == 5
      assert reloaded.public == true
    end

    test "applies a delta whatever the writer saw" do
      row = create_counter(1)

      # Below every revision the row holds and based on nothing: a PUT with this stamp is dropped
      # by the merge, which is what the second batch below proves.
      stale = row.__meta__.revisions.count - 1

      moved =
        update_write(Module20, row.id, nil,
          claim: ["authorize", "update"],
          deltas: %{"count" => 2},
          stamp: stale
        )

      assert run(envelope([moved]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      reloaded = EntityOperations.get(Module20, row.id)

      assert reloaded.count == 3
      assert reloaded.__meta__.revisions.count > row.__meta__.revisions.count

      put =
        update_write(Module20, row.id, %{"count" => 9},
          claim: ["authorize", "update"],
          stamp: stale
        )

      assert {:ok, answer} = run(envelope([put], seq: 2), server())

      assert answer["dropped"] == %{"0" => %{"count" => 9}}
      assert answer["kept"]["0"]["count"] == 3

      assert EntityOperations.get(Module20, row.id).count == 3
    end

    test "adds up deltas from two batches authored against one value" do
      row = create_counter(1)

      write =
        update_write(Module20, row.id, nil,
          claim: ["authorize", "update"],
          deltas: %{"count" => 1},
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert run(envelope([write], replica_id: Entity.generate_id()), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(Module20, row.id).count == 3
    end

    test "applies a delta beside a set" do
      row = create_counter(1)

      write =
        update_write(Module20, row.id, %{"label" => "moved"},
          based_on: %{"label" => row.__meta__.revisions.label},
          claim: ["authorize", "update"],
          deltas: %{"count" => 1},
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      reloaded = EntityOperations.get(Module20, row.id)

      assert reloaded.label == "moved"
      assert reloaded.count == 2
    end

    test "refuses a move past what the column can hold" do
      row = create_counter(9_223_372_036_854_775_807)

      write =
        update_write(Module20, row.id, nil,
          claim: ["authorize", "update"],
          deltas: %{"count" => 1},
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server()) ==
               rejected(0, %{count: [{:type, :integer}]})

      assert EntityOperations.get(Module20, row.id).count == 9_223_372_036_854_775_807
    end

    test "applies a delete the writer is based on" do
      user = create_user("remover@example.com")
      row = create_archivable(user, priority: 5)

      write =
        delete_write(PolicyModule1, row.id,
          based_on: based_on(row),
          claim: ["authorize", "archive"],
          stamp: stamp_above(row)
        )

      assert {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}} =
               run(envelope([write]), server(user.id))

      assert EntityOperations.get(PolicyModule1, row.id) == nil
    end

    test "drops a delete when a column moved past it, naming every column and the row that stands" do
      user = create_user("blocked@example.com")
      row = create_archivable(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(PolicyModule1, row.id, %{"priority" => newer})

      write =
        delete_write(PolicyModule1, row.id,
          based_on: %{"priority" => row.__meta__.revisions.priority},
          claim: ["authorize", "archive"],
          stamp: newer - 1
        )

      assert {:ok, answer} = run(envelope([write]), server(user.id))

      assert answer["dropped"] == %{"0" => %{"priority" => nil}}

      # A dropped delete kept the WHOLE row, which is what tells a client the row is still there -
      # its own copy is already gone, and a patch for a row it does not hold is passed over.
      assert answer["kept"]["0"]["id"] == row.id
      assert answer["kept"]["0"]["priority"] == 5
      assert answer["kept"]["0"]["$revisions"]["priority"] == newer

      assert EntityOperations.get(PolicyModule1, row.id) != nil
    end

    test "treats a delete of a row that is not there as done" do
      write = delete_write(Module2, Entity.generate_id())

      assert run(envelope([write]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
    end

    test "applies an added edge" do
      source = create_source()
      target = create_target()

      write = edge_write("add_relationship", Module16, source.id, "secrets", target.id)

      assert {:ok, %{"status" => "confirmed"}} = run(envelope([write]), server())

      assert count_edges(source.id, target.id) == 1
    end

    test "applies a deleted edge" do
      source = create_source()
      target = create_target()

      :ok = EntityOperations.add_relationship(Module16, source.id, :secrets, target.id)

      write = edge_write("delete_relationship", Module16, source.id, "secrets", target.id)

      assert {:ok, %{"status" => "confirmed"}} = run(envelope([write]), server())

      assert count_edges(source.id, target.id) == 0
    end

    test "refuses an update naming a row that is not there" do
      write = update_write(Module2, Entity.generate_id(), %{"c" => "x"})

      assert run(envelope([write]), server()) == rejected(0, :not_found)
    end

    test "refuses an edge naming a row that is not there" do
      target = create_target()

      write =
        edge_write("add_relationship", Module16, Entity.generate_id(), "secrets", target.id)

      assert run(envelope([write]), server()) == rejected(0, :not_found)
    end

    # A client is never the trusted tier: with nobody signed in the write is evaluated under the
    # anonymous semantics rather than written raw, and Module1 grants :create to nobody.
    test "evaluates an unclaimed create under an anonymous session" do
      write = create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server())

      assert reason =~ "not allowed to create Hologram.Test.Fixtures.Policy.Module1"
    end

    test "refuses a denied claim and names the write it refused" do
      landing_id = Entity.generate_id()

      writes = [
        publish_write(landing_id),
        create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})
      ]

      assert {:ok, %{"status" => "rejected", "write" => 1}} = run(envelope(writes), server())

      # The whole batch rolled back, including the write that had already landed.
      assert EntityOperations.get(PolicyModule2, landing_id) == nil
    end

    # Module2's roles extend nothing, so under a bare grant_role line each role may grant only
    # itself - a member brings in a member.
    test "lands a role grant under a holder who may grant it" do
      member = create_user("grant-member@example.com")
      user = create_user("grant-user@example.com")
      resource = create_shared()
      replica_id = Entity.generate_id()

      Auth.grant_role(member, resource, :member)

      write = grant_write(user.id, resource, :member)

      assert run(envelope([write], replica_id: replica_id), server(member.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      # The granter is the acting user, whatever the client put in the write.
      row = EntityOperations.get(RoleGrant, write["id"])

      assert row.granted_by_id == member.id
      assert row.role == :member
      assert row.user_id == user.id

      # The effect carries the batch's own reference, like any row's.
      assert [%{type: "Hologram.Auth.RoleGrant", entity_id: entity_id, mutation_ref: ref}] =
               outbox_rows(replica_id)

      assert entity_id == write["id"]
      assert ref["replica_id"] == replica_id
    end

    # The browser writes the creator's grants beside its own create, under the ids the server
    # derives for the same grants - so what it holds at once and what create/1 writes are one row,
    # answered here as a grant already held. Module1 lets only an owner grant and this user holds
    # nothing there, so the batch lands only because a creator's grant asks no gate.
    test "lands a creator's grant beside the create that earned it" do
      user = create_user("creator-grant@example.com")
      entity_id = Entity.generate_id()

      writes = [
        create_write(PolicyModule1, entity_id, %{"author_id" => user.id},
          claim: ["authorize", "archive"]
        ),
        grant_write(user.id, %PolicyModule1{id: entity_id}, :maintainer)
      ]

      assert {:ok, %{"status" => "confirmed", "dropped" => dropped, "kept" => kept}} =
               run(envelope(writes), server(user.id))

      assert Map.keys(dropped["1"]) == [
               "entity_id",
               "entity_type",
               "granted_by_id",
               "role",
               "user_id"
             ]

      grant_id =
        RoleGrant.derive_id(user.id, PolicyModule1, entity_id, :maintainer)

      assert kept["1"]["id"] == grant_id

      row = EntityOperations.get(RoleGrant, grant_id)

      assert row.granted_by_id == user.id
      assert row.entity_id == entity_id
      assert row.role == :maintainer
      assert row.user_id == user.id
    end

    # The id is derived from the grant, so the row found by the write's id IS the stored grant -
    # and kept says who really made it, not who asked again.
    test "answers a grant already held with the stored row" do
      first_member = create_user("first-member@example.com")
      second_member = create_user("second-member@example.com")
      user = create_user("held-user@example.com")
      resource = create_shared()

      Auth.grant_role(first_member, resource, :member)
      Auth.grant_role(second_member, resource, :member)

      Context.with_actor(first_member.id, fn ->
        Auth.grant_role(user, resource, :member)
      end)

      write = grant_write(user.id, resource, :member)

      assert {:ok, %{"status" => "confirmed", "dropped" => dropped, "kept" => kept}} =
               run(envelope([write]), server(second_member.id))

      assert Map.keys(dropped["0"]) == [
               "entity_id",
               "entity_type",
               "granted_by_id",
               "role",
               "user_id"
             ]

      assert kept["0"]["id"] == write["id"]
      assert kept["0"]["granted_by_id"] == first_member.id
    end

    test "rolls the batch back on a refused grant" do
      member = create_user("rollback-member@example.com")
      user = create_user("rollback-user@example.com")
      resource = create_shared()
      landing_id = Entity.generate_id()

      Auth.grant_role(member, resource, :member)

      writes = [publish_write(landing_id), grant_write(user.id, resource, :admin)]

      assert {:ok, %{"status" => "rejected", "write" => 1}} =
               run(envelope(writes), server(member.id))

      assert EntityOperations.get(PolicyModule2, landing_id) == nil
    end

    test "rejects a grant of a role above the holder's own" do
      member = create_user("escalating-member@example.com")
      user = create_user("escalation-user@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      write = grant_write(user.id, resource, :admin)

      message =
        "the acting user holds :member on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)}, " <>
          "which may grant :member but not :admin. " <>
          "Declare `allow {:grant_role, :admin}, to: :member` on Hologram.Test.Fixtures.Policy.Module2 if that is intended."

      assert run(envelope([write]), server(member.id)) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    # No writer of the store produces such a row now - every one derives the id - so a row that
    # conflicts on the fact yet is not found by the derived id is an invariant broken, and the
    # applier says so rather than retrying the insert forever.
    test "raises on a grant held under an id that is not its derivation" do
      member = create_user("legacy-member@example.com")
      user = create_user("legacy-user@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      EntityOperations.create_if_absent(%RoleGrant{
        id: Entity.generate_id(),
        entity_id: resource.id,
        entity_type: PolicyModule2,
        role: :member,
        user_id: user.id
      })

      write = grant_write(user.id, resource, :member)

      expected_msg =
        "a role grant for this user, resource and role exists under an id that is not its " <>
          "derivation - every grant row's id is derived from the grant it states"

      assert_error ArgumentError, expected_msg, fn ->
        run(envelope([write]), server(member.id))
      end
    end

    test "rejects a grant to a user that does not exist" do
      member = create_user("granting-to-nobody@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      write = grant_write(Entity.generate_id(), resource, :member)

      assert run(envelope([write]), server(member.id)) == rejected(0, %{user_id: [:not_found]})
    end

    test "rejects a type-wide grant" do
      admin = create_user("type-wide-admin@example.com")
      user = create_user("type-wide-user@example.com")
      entity_type = PolicyModule2

      data = %{
        "granted_by_id" => admin.id,
        "entity_id" => nil,
        "entity_type" => Codec.encode_enum_value(entity_type),
        "role" => "member",
        "user_id" => user.id
      }

      id = RoleGrant.derive_id(user.id, entity_type, nil, :member)
      write = create_write(RoleGrant, id, data)

      message = "type-wide roles are granted only by trusted code running without an acting user"

      assert run(envelope([write]), server(admin.id)) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "rejects a grant from an anonymous session" do
      user = create_user("anonymous-grant-user@example.com")
      resource = create_shared()

      write = grant_write(user.id, resource, :member)

      message = "a role is granted only by a signed-in user - nobody is signed in"

      assert run(envelope([write]), server()) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "lands a revocation of another user's role" do
      member = create_user("revoking-member@example.com")
      target = create_user("revoked-member@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)
      Auth.grant_role(target, resource, :member)

      row = EntityOperations.get(RoleGrant, grant_id(target.id, resource, :member))

      write =
        revocation_write(target.id, resource, :member,
          based_on: based_on(row),
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server(member.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(RoleGrant, row.id) == nil
    end

    test "lands a user's own revocation" do
      member = create_user("staying-member@example.com")
      leaver = create_user("leaving-member@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)
      Auth.grant_role(leaver, resource, :member)

      row = EntityOperations.get(RoleGrant, grant_id(leaver.id, resource, :member))

      write =
        revocation_write(leaver.id, resource, :member,
          based_on: based_on(row),
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server(leaver.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(RoleGrant, row.id) == nil
    end

    # The id is derived from the grant, so a grant revoked and made again is the SAME row with
    # newer revisions - and a revocation still based on the earlier grant loses to it, the way
    # any delete loses to a column that moved past it. The stamp sits above the first grant's
    # revisions (the clock check needs that) and not above the second's.
    test "drops a revocation based on revisions a newer grant has moved past" do
      member = create_user("stale-revoker@example.com")
      user = create_user("regranted-user@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)
      Auth.grant_role(user, resource, :member)

      first_row = EntityOperations.get(RoleGrant, grant_id(user.id, resource, :member))
      first_stamp = first_row.__meta__.revisions.role

      Auth.revoke_role(user, resource, :member)
      Auth.grant_role(user, resource, :member)

      write =
        revocation_write(user.id, resource, :member,
          based_on: based_on(first_row),
          stamp: first_stamp + 1
        )

      assert {:ok, %{"status" => "confirmed", "dropped" => dropped, "kept" => kept}} =
               run(envelope([write]), server(member.id))

      assert Map.keys(dropped["0"]) == [
               "entity_id",
               "entity_type",
               "granted_by_id",
               "role",
               "user_id"
             ]

      assert kept["0"]["id"] == first_row.id
      assert EntityOperations.get(RoleGrant, first_row.id) != nil
    end

    # A grant's id is derivable from its grant, so a delete of it is something anyone can send -
    # and a stale one would otherwise answer with the stored row as what was kept. The gate runs
    # first: nobody signed in gets the refusal and not the row.
    test "refuses a stale revocation from an anonymous session without answering the row" do
      member = create_user("probed-member@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      write = revocation_write(member.id, resource, :member, stamp: 1)

      message = "a role is revoked only by a signed-in user - nobody is signed in"

      assert run(envelope([write]), server()) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "refuses a stale revocation the acting user may not make without answering the row" do
      member = create_user("probed-again-member@example.com")
      stranger = create_user("stranger@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      write = revocation_write(member.id, resource, :member, stamp: 1)

      message =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)} that may revoke :member"

      assert run(envelope([write]), server(stranger.id)) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "refuses an anonymous revocation of a row already gone" do
      user = create_user("gone-anonymous-user@example.com")
      resource = create_shared()

      write = revocation_write(user.id, resource, :member)

      message = "a role is revoked only by a signed-in user - nobody is signed in"

      assert run(envelope([write]), server()) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "confirms a revocation of a row already gone" do
      member = create_user("gone-revoker@example.com")
      user = create_user("never-granted-user@example.com")
      resource = create_shared()

      Auth.grant_role(member, resource, :member)

      write = revocation_write(user.id, resource, :member)

      assert run(envelope([write]), server(member.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
    end

    test "confirms a user's own revocation of a row already gone" do
      leaver = create_user("gone-leaver@example.com")
      resource = create_shared()

      write = revocation_write(leaver.id, resource, :member)

      assert run(envelope([write]), server(leaver.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}
    end

    # The gate is asked about the grant the write states, not about the row - so an actor who may
    # not revoke it is refused the same way whether or not the row is there, and a delete of a
    # derived id says nothing about whether the grant exists.
    test "refuses a revocation of a row already gone the acting user may not make" do
      stranger = create_user("gone-stranger@example.com")
      user = create_user("never-granted-again-user@example.com")
      resource = create_shared()

      write = revocation_write(user.id, resource, :member)

      message =
        "the acting user holds no role on Hologram.Test.Fixtures.Policy.Module2 #{inspect(resource.id)} that may revoke :member"

      assert run(envelope([write]), server(stranger.id)) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "lands a job queued, with the session's user as its actor" do
      user = create_user("job-enqueuer@example.com")
      id = Entity.generate_id()

      assert run(envelope([create_write(JobModule1, id, %{})]), server(user.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      job = EntityOperations.get(JobModule1, id)

      assert job.status == :queued
      assert job.actor_id == user.id
      assert job.error == nil
    end

    test "refuses a job with the batch it rode in" do
      user = create_user("job-loser@example.com")
      job_id = Entity.generate_id()

      writes = [
        create_write(JobModule1, job_id, %{}),
        create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})
      ]

      assert {:ok, %{"status" => "rejected", "write" => 1}} =
               run(envelope(writes), server(user.id))

      assert EntityOperations.get(JobModule1, job_id) == nil
    end

    test "refuses a value the declarations refuse" do
      write = readable_write(Module19, Entity.generate_id(), %{"code" => "c"})

      assert run(envelope([write]), server()) == rejected(0, %{slug: [:required]})
    end

    test "refuses a duplicate of a unique value" do
      %{slug: "taken"}
      |> Module19.new()
      |> DB.create!()

      write = readable_write(Module19, Entity.generate_id(), %{"slug" => "taken"})

      assert run(envelope([write]), server()) == rejected(0, %{slug: [:unique]})
    end

    test "refuses a reference naming no row" do
      write =
        readable_write(Module3, Entity.generate_id(), %{"c_id" => Entity.generate_id()})

      assert run(envelope([write]), server()) == rejected(0, %{c_id: [:not_found]})
    end

    test "refuses a delete the row's references block" do
      required_target = DB.create!(Module1.new())

      referenced =
        %{a: true, c: "x"}
        |> Module2.new()
        |> DB.create!()

      %{b_id: referenced.id, c_id: required_target.id}
      |> Module3.new()
      |> DB.create!()

      # The delete has to WIN the merge to reach the executor at all - a client holding the row
      # sends its revisions, and a stamp from the wall clock alone can sit below them.
      write =
        delete_write(Module2, referenced.id,
          based_on: based_on(referenced),
          claim: ["authorize", "read"],
          stamp: stamp_above(referenced)
        )

      assert run(envelope([write]), server()) ==
               rejected(0, %{referenced_by: Module3, relationship: :b})
    end

    test "keeps a batch the evaluator refused, with what it carried and the answer it got" do
      user = create_user("refused@example.com")
      replica_id = Entity.generate_id()
      write = create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})
      raw = envelope([write], replica_id: replica_id)

      assert {:ok, %{"status" => "rejected"} = answer} = run(raw, server(user.id))

      assert Record.find(replica_id, 1) == %{actor_id: user.id, result: answer}
      assert record_envelope(replica_id, 1) == raw
    end

    test "answers a refused batch sent again from its record without evaluating it again" do
      user = create_user("resender@example.com")
      id = Entity.generate_id()
      raw = envelope([update_write(PolicyModule1, id, %{"priority" => 9})])

      assert run(raw, server(user.id)) == rejected(0, :not_found)

      # The world changed between the two sends - a second evaluation would find the row and land
      # the update - and the answer did not, which is what proves it came from the record.
      create_archivable(user, id: id, priority: 5)

      assert run(raw, server(user.id)) == rejected(0, :not_found)
      assert EntityOperations.get(PolicyModule1, id).priority == 5
    end

    test "keeps nothing of a batch refused under an anonymous session" do
      replica_id = Entity.generate_id()
      target_id = Entity.generate_id()
      write = readable_write(Module3, Entity.generate_id(), %{"c_id" => target_id})
      raw = envelope([write], replica_id: replica_id)

      assert run(raw, server()) == rejected(0, %{c_id: [:not_found]})
      assert Record.find(replica_id, 1) == nil

      # Nothing kept means no key taken: the same batch sent again is evaluated on its own, and
      # lands once the row its reference names exists.
      %{id: target_id}
      |> Module1.new()
      |> DB.create!()

      assert {:ok, %{"status" => "confirmed"}} = run(raw, server())
    end

    test "keeps nothing of a batch refused for its clock" do
      user = create_user("fastclock@example.com")
      replica_id = Entity.generate_id()
      a_year_ahead = (System.os_time(:millisecond) + 365 * 86_400_000) * 1024
      write = publish_write(Entity.generate_id(), stamp: a_year_ahead)

      assert run(envelope([write], replica_id: replica_id), server(user.id)) ==
               rejected(0, :clock)

      assert Record.find(replica_id, 1) == nil
    end

    test "keeps no envelope of a batch that landed" do
      replica_id = Entity.generate_id()
      raw = envelope([publish_write(Entity.generate_id())], replica_id: replica_id)

      assert {:ok, %{"status" => "confirmed"}} = run(raw, server())

      assert record_envelope(replica_id, 1) == nil

      assert Record.find(replica_id, 1).result ==
               %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}
    end

    test "leaves no effect of a refused batch" do
      user = create_user("noeffect@example.com")
      replica_id = Entity.generate_id()
      id = Entity.generate_id()
      write = readable_write(Module19, id, %{"code" => "c"})

      assert {:ok, %{"status" => "rejected"}} =
               run(envelope([write], replica_id: replica_id), server(user.id))

      # The record is not an effect: it says the batch was refused, and nothing the batch wrote
      # survived it.
      assert Record.find(replica_id, 1) != nil
      assert outbox_rows(replica_id) == []
      assert EntityOperations.get(Module19, id) == nil
    end

    test "refuses a batch whose replica and sequence number belong to another session" do
      sender = create_user("sender@example.com")
      other = create_user("other@example.com")
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(sender.id))

      assert run(batch, server(other.id)) == rejected(nil, :forged_client)

      # The record still belongs to the session that earned it.
      assert Record.find(batch["replica_id"], 1).actor_id == sender.id
    end

    test "refuses a signed-in session's batch claimed anonymously" do
      sender = create_user("owner@example.com")
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(sender.id))

      assert run(batch, server()) == rejected(nil, :forged_client)
    end

    test "refuses an anonymous batch claimed by a signed-in session" do
      user = create_user("claimant@example.com")
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server())

      assert run(batch, server(user.id)) == rejected(nil, :forged_client)
    end

    test "refuses a stamp running ahead of the server's clock and names the write" do
      id = Entity.generate_id()
      a_year_ahead = (System.os_time(:millisecond) + 365 * 86_400_000) * 1024
      replica_id = Entity.generate_id()
      write = publish_write(id, stamp: a_year_ahead)

      assert run(envelope([write], replica_id: replica_id), server()) == rejected(0, :clock)

      assert EntityOperations.get(PolicyModule2, id) == nil
      assert Record.find(replica_id, 1) == nil
    end

    test "accepts a stamp within the allowance" do
      id = Entity.generate_id()
      four_minutes_ahead = (System.os_time(:millisecond) + 4 * 60_000) * 1024

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([publish_write(id, stamp: four_minutes_ahead)]), server())

      assert EntityOperations.get(PolicyModule2, id) != nil
    end

    test "refuses a stamp not above the revisions its write was based on" do
      user = create_user("backwards@example.com")
      row = create_archivable(user, priority: 5)
      seen = row.__meta__.revisions.priority

      write =
        update_write(PolicyModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => seen},
          stamp: seen
        )

      assert run(envelope([write]), server(user.id)) == rejected(0, :clock)
      assert EntityOperations.get(PolicyModule1, row.id).priority == 5
    end

    test "refuses a batch built against another model" do
      id = Entity.generate_id()
      replica_id = Entity.generate_id()
      write = create_write(Module2, id, %{"c" => "x"})

      raw = envelope([write], replica_id: replica_id, model_hash: "other")

      assert run(raw, server()) == rejected(nil, :stale_build)

      assert EntityOperations.get(Module2, id) == nil
      assert Record.find(replica_id, 1) == nil
    end

    test "answers a malformed envelope with what is wrong" do
      assert run(%{envelope([]) | "writes" => "nope"}, server()) ==
               {:invalid, "writes must be a list"}
    end

    test "answers an envelope carrying no model hash with what is wrong" do
      assert run(%{envelope([]) | "model_hash" => 1}, server()) ==
               {:invalid, "model_hash must be a string"}
    end
  end
end
