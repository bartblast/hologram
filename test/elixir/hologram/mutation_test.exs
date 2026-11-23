defmodule Hologram.MutationTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Mutation

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Record
  alias Hologram.Runtime.Serializer
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module20
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module53
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.Fixtures.Mutation.Module1, as: MutationModule1
  alias Hologram.Test.Fixtures.Mutation.Module2, as: MutationModule2
  alias Hologram.Test.Fixtures.Mutation.Module3, as: MutationModule3
  alias Hologram.Test.Fixtures.Mutation.Module4, as: MutationModule4
  alias Hologram.Test.Fixtures.Mutation.Module5, as: MutationModule5
  alias Hologram.Test.Fixtures.Mutation.Module6, as: MutationModule6
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module38, as: Channel

  # A repeated grant by a type-wide holder, already answered once, for a test to change the store
  # before sending the batch again.
  defp answered_repeat do
    %{holder: holder, write: write} = context = repeated_grant()
    batch = envelope([write])

    {:ok, %{"status" => "confirmed", "kept" => %{"0" => %{"id" => _id}}}} =
      run(batch, server(holder.id))

    Map.put(context, :batch, batch)
  end

  # A row whose author is the given user, whose writes `when: author_id == user_id()` grants that
  # user - write rules that need no role grant, on a multi-column type.
  defp create_authored(user, values) do
    values
    |> Keyword.put(:author_id, user.id)
    |> MutationModule1.new()
    |> DB.create!()
  end

  # What a client holding this row would send as `based_on` - its whole revisions map, keyed the
  # way the wire keys it. A delete touches every column, so it carries all of them.
  defp based_on(row) do
    Map.new(row.__meta__.revisions, fn {name, revision} -> {Atom.to_string(name), revision} end)
  end

  defp count_edges(entity_type, relationship, source_id, target_id) do
    statement =
      ~s|SELECT count(*) FROM "hologram_data"."#{DB.join_table_name(entity_type, relationship)}" | <>
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

  # A row Mutation.Module6's rule lets anyone update while it's open and holds no locked tag.
  defp create_ticket(status) do
    [status: status]
    |> MutationModule6.new()
    |> DB.create!()
  end

  defp create_tag(label) do
    %{label: label, token: "t"}
    |> Module15.new()
    |> DB.create!()
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
      "stamp" => Keyword.get(opts, :stamp, stamp())
    }
  end

  defp edge_write(op, entity_type, id, relationship, target_id) do
    %{
      "op" => op,
      "type" => inspect(entity_type),
      "id" => id,
      "relationship" => relationship,
      "target_id" => target_id
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

  # Scoped to one batch by its own mutation_ref: the oplog is shared, and what these ask about is
  # the effects of the batch under test rather than everything the table happens to hold.
  defp oplog_rows(replica_id) do
    statement = """
    SELECT "type", "entity_id", "actor_id", "mutation_ref"
    FROM "hologram_system"."oplog"
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

  # A grant someone else made on a row, and the same grant as a holder of the role on the whole
  # type would send it again.
  defp repeated_grant do
    holder = create_user("repeat-holder@example.com")
    granter = create_user("repeat-granter@example.com")
    user = create_user("repeat-grantee@example.com")
    resource = create_shared()

    Auth.grant_role(holder, :member, PolicyModule2)
    Auth.grant_role(granter, :member, resource)

    Context.with_actor(granter.id, fn ->
      Auth.grant_role(user, :member, resource)
    end)

    %{
      granter: granter,
      holder: holder,
      resource: resource,
      user: user,
      write: grant_write(user.id, resource, :member)
    }
  end

  # A create anyone may make: Mutation.Module2 grants it for a public row.
  defp public_write(id, opts \\ []) do
    create_write(MutationModule2, id, %{"public" => true}, opts)
  end

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
       "reason" => Serializer.serialize!(reason),
       "status" => "rejected",
       "write" => index
     }}
  end

  # Marks the entry as part of the call the entry before it came from.
  defp same_call(entry), do: Map.put(entry, "same_call", true)

  defp server(user_id \\ nil), do: %Server{user_id: user_id}

  defp update_write(entity_type, id, data, opts \\ []) do
    base = %{
      "op" => "update",
      "type" => inspect(entity_type),
      "id" => id,
      "based_on" => Keyword.get(opts, :based_on),
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

      assert run(envelope([public_write(id)]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(MutationModule2, id).public == true
    end

    test "applies every write of a batch" do
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      writes = [public_write(first_id), public_write(second_id)]

      assert {:ok, %{"status" => "confirmed"}} = run(envelope(writes), server())

      assert EntityOperations.get(MutationModule2, first_id) != nil
      assert EntityOperations.get(MutationModule2, second_id) != nil
    end

    test "stores the writer's stamp as every column's revision" do
      id = Entity.generate_id()
      writer_stamp = stamp()

      run(envelope([public_write(id, stamp: writer_stamp)]), server())

      assert EntityOperations.get(MutationModule2, id).__meta__.revisions == %{
               public: writer_stamp
             }
    end

    # Written offline an hour ago and arriving now: the writer's pair says when it was made, the
    # server's pair when it got here - which is what tells everyone else it is new.
    test "files a create written earlier under its writer's time and its arrival" do
      id = Entity.generate_id()
      written_ms = System.os_time(:millisecond) - 3_600_000

      run(envelope([public_write(id, stamp: written_ms * 1024)]), server())

      row = EntityOperations.get(MutationModule2, id)

      assert DateTime.to_unix(row.created_at, :millisecond) == written_ms
      assert DateTime.compare(row.server_created_at, row.created_at) == :gt
      assert row.server_updated_at == row.server_created_at
    end

    test "records the batch on the effect it wrote" do
      id = Entity.generate_id()
      replica_id = Entity.generate_id()

      run(envelope([public_write(id)], replica_id: replica_id, seq: 7), server())

      assert [%{entity_id: ^id, mutation_ref: %{"replica_id" => ^replica_id, "seq" => 7}}] =
               oplog_rows(replica_id)
    end

    test "records the acting user on the effect" do
      user = create_user("publisher@example.com")
      id = Entity.generate_id()
      replica_id = Entity.generate_id()

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([public_write(id)], replica_id: replica_id), server(user.id))

      assert [%{actor_id: actor_id}] = oplog_rows(replica_id)
      assert actor_id == user.id
    end

    test "records the applied batch" do
      replica_id = Entity.generate_id()

      run(
        envelope([public_write(Entity.generate_id())], replica_id: replica_id, seq: 3),
        server()
      )

      assert Record.find(replica_id, 3).result ==
               %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}
    end

    test "answers a repeated batch from the record without applying it again" do
      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"} = answer} = run(batch, server())
      assert run(batch, server()) == {:ok, answer}

      assert length(oplog_rows(batch["replica_id"])) == 1
    end

    test "applies each sequence number of one replica on its own" do
      replica_id = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([public_write(first_id)], replica_id: replica_id, seq: 1), server())
      run(envelope([public_write(second_id)], replica_id: replica_id, seq: 2), server())

      assert EntityOperations.get(MutationModule2, first_id) != nil
      assert EntityOperations.get(MutationModule2, second_id) != nil

      assert Record.find(replica_id, 1) != nil
      assert Record.find(replica_id, 2) != nil
    end

    test "applies one sequence number for each replica on its own" do
      first_client = Entity.generate_id()
      second_client = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([public_write(first_id)], replica_id: first_client, seq: 1), server())
      run(envelope([public_write(second_id)], replica_id: second_client, seq: 1), server())

      assert EntityOperations.get(MutationModule2, first_id) != nil
      assert EntityOperations.get(MutationModule2, second_id) != nil

      assert Record.find(first_client, 1) != nil
      assert Record.find(second_client, 1) != nil
    end

    test "applies an update to the columns the writer saw unchanged" do
      user = create_user("author@example.com")
      row = create_authored(user, priority: 5)
      writer_stamp = row.__meta__.revisions.priority + 1_000_000

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: writer_stamp
        )

      assert run(envelope([write]), server(user.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      reloaded = EntityOperations.get(MutationModule1, row.id)

      assert reloaded.priority == 9
      assert reloaded.__meta__.revisions.priority == writer_stamp
      assert reloaded.__meta__.revisions.public == row.__meta__.revisions.public
    end

    test "drops a column the row holds a newer revision of, naming what lost and what stands" do
      user = create_user("outrun@example.com")
      row = create_authored(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, answer} = run(envelope([write]), server(user.id))

      assert answer["dropped"] == %{"0" => %{"priority" => 9}}

      # What WON, so a client can show it the moment the answer lands rather than waiting for the
      # frame that carries it.
      assert answer["kept"]["0"]["priority"] == 5
      assert answer["kept"]["0"]["$revisions"]["priority"] == newer

      assert EntityOperations.get(MutationModule1, row.id).priority == 5
    end

    test "names a big integer that lost and the one that stands as the browser reads them" do
      user = create_user("outrun_big@example.com")
      row = create_authored(user, priority: 9_007_199_254_740_993)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      write =
        update_write(MutationModule1, row.id, %{"priority" => "9007199254740995"},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, answer} = run(envelope([write]), server(user.id))

      assert answer["dropped"] == %{"0" => %{"priority" => "9007199254740995"}}
      assert answer["kept"]["0"]["priority"] == "9007199254740993"
    end

    # Nothing changed on the server, so its update time says the row last changed when it did. A
    # value planted months back, so a statement run in the same millisecond as the create could
    # not leave the column looking untouched.
    test "leaves server_updated_at alone when every value of an update loses" do
      user = create_user("outrun_whole@example.com")
      row = create_authored(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000
      planted_at = ~U[2026-01-15 10:30:00.000000Z]

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      {:ok, _result} =
        Connection.query(
          ~s|UPDATE "hologram_data"."#{Mapper.table_name(MutationModule1)}" | <>
            ~s|SET "server_updated_at" = $1 WHERE "id" = $2|,
          [Codec.encode(planted_at, :datetime), Codec.encode(row.id, :uuid)]
        )

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, %{"dropped" => %{"0" => %{"priority" => 9}}}} =
               run(envelope([write]), server(user.id))

      assert EntityOperations.get(MutationModule1, row.id).server_updated_at == planted_at
    end

    test "applies the rest of an update whose column was dropped" do
      user = create_user("partial@example.com")
      row = create_authored(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9, "public" => true},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, %{"dropped" => %{"0" => %{"priority" => 9}}}} =
               run(envelope([write]), server(user.id))

      reloaded = EntityOperations.get(MutationModule1, row.id)

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
          deltas: %{"count" => 2},
          stamp: stale
        )

      assert run(envelope([moved]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      reloaded = EntityOperations.get(Module20, row.id)

      assert reloaded.count == 3
      assert reloaded.__meta__.revisions.count > row.__meta__.revisions.count

      put =
        update_write(Module20, row.id, %{"count" => 9}, stamp: stale)

      assert {:ok, answer} = run(envelope([put], seq: 2), server())

      assert answer["dropped"] == %{"0" => %{"count" => 9}}
      assert answer["kept"]["0"]["count"] == 3

      assert EntityOperations.get(Module20, row.id).count == 3
    end

    test "adds up deltas from two batches authored against one value" do
      row = create_counter(1)

      write =
        update_write(Module20, row.id, nil,
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
          deltas: %{"count" => 1},
          stamp: stamp_above(row)
        )

      assert run(envelope([write]), server()) ==
               rejected(0, %{count: [{:type, :integer}]})

      assert EntityOperations.get(Module20, row.id).count == 9_223_372_036_854_775_807
    end

    test "applies a delete the writer is based on" do
      user = create_user("remover@example.com")
      row = create_authored(user, priority: 5)

      write =
        delete_write(MutationModule1, row.id,
          based_on: based_on(row),
          stamp: stamp_above(row)
        )

      assert {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}} =
               run(envelope([write]), server(user.id))

      assert EntityOperations.get(MutationModule1, row.id) == nil
    end

    test "drops a delete when a column moved past it, naming every column and the row that stands" do
      user = create_user("blocked@example.com")
      row = create_authored(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      write =
        delete_write(MutationModule1, row.id,
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert {:ok, answer} = run(envelope([write]), server(user.id))

      assert answer["dropped"] == %{"0" => %{"priority" => nil}}

      # A dropped delete kept the WHOLE row, which is what tells a client the row is still there -
      # its own copy is already gone, and a patch for a row it does not hold is passed over.
      assert answer["kept"]["0"]["id"] == row.id
      assert answer["kept"]["0"]["priority"] == 5
      assert answer["kept"]["0"]["$revisions"]["priority"] == newer

      assert EntityOperations.get(MutationModule1, row.id) != nil
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

      assert count_edges(Module16, :secrets, source.id, target.id) == 1
    end

    test "applies a deleted edge" do
      source = create_source()
      target = create_target()

      :ok = EntityOperations.add_relationship(Module16, source.id, :secrets, target.id)

      write = edge_write("delete_relationship", Module16, source.id, "secrets", target.id)

      assert {:ok, %{"status" => "confirmed"}} = run(envelope([write]), server())

      assert count_edges(Module16, :secrets, source.id, target.id) == 0
    end

    # The server verb judges the whole call against the row it started from, so a status it closes
    # doesn't refuse the tag it adds.
    test "lands a call that puts a value its rule reads and adds an edge" do
      ticket = create_ticket("open")
      tag = create_tag("plain")

      writes = [
        update_write(MutationModule6, ticket.id, %{"status" => "closed"},
          stamp: stamp_above(ticket)
        ),
        same_call(edge_write("add_relationship", MutationModule6, ticket.id, "tags", tag.id))
      ]

      assert run(envelope(writes), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      assert EntityOperations.get(MutationModule6, ticket.id).status == "closed"
      assert count_edges(MutationModule6, :tags, ticket.id, tag.id) == 1
    end

    test "lands a call that puts a value its rule reads and deletes an edge" do
      ticket = create_ticket("open")
      tag = create_tag("plain")

      :ok = EntityOperations.add_relationship(MutationModule6, ticket.id, :tags, tag.id)

      writes = [
        update_write(MutationModule6, ticket.id, %{"status" => "closed"},
          stamp: stamp_above(ticket)
        ),
        same_call(edge_write("delete_relationship", MutationModule6, ticket.id, "tags", tag.id))
      ]

      assert {:ok, %{"status" => "confirmed"}} = run(envelope(writes), server())

      assert EntityOperations.get(MutationModule6, ticket.id).status == "closed"
      assert count_edges(MutationModule6, :tags, ticket.id, tag.id) == 0
    end

    test "lands an edge-only call whose first edge would refuse the second on its own" do
      ticket = create_ticket("open")
      locked = create_tag("locked")
      plain = create_tag("plain")

      writes = [
        edge_write("add_relationship", MutationModule6, ticket.id, "tags", locked.id),
        same_call(edge_write("add_relationship", MutationModule6, ticket.id, "tags", plain.id))
      ]

      assert {:ok, %{"status" => "confirmed"}} = run(envelope(writes), server())

      assert count_edges(MutationModule6, :tags, ticket.id, locked.id) == 1
      assert count_edges(MutationModule6, :tags, ticket.id, plain.id) == 1
    end

    test "judges a separate call against the row the call before it left" do
      ticket = create_ticket("open")
      tag = create_tag("plain")

      writes = [
        update_write(MutationModule6, ticket.id, %{"status" => "closed"},
          stamp: stamp_above(ticket)
        ),
        edge_write("add_relationship", MutationModule6, ticket.id, "tags", tag.id)
      ]

      assert {:ok, %{"status" => "rejected", "write" => 1, "reason" => reason}} =
               run(envelope(writes), server())

      assert reason =~ "no allow line that holds covers :tags"
      assert EntityOperations.get(MutationModule6, ticket.id).status == "open"
    end

    test "refuses a call by its first write, naming every field it changes" do
      ticket = create_ticket("closed")
      tag = create_tag("plain")

      writes = [
        update_write(MutationModule6, ticket.id, %{"status" => "archived"},
          stamp: stamp_above(ticket)
        ),
        same_call(edge_write("add_relationship", MutationModule6, ticket.id, "tags", tag.id))
      ]

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope(writes), server())

      assert reason =~ "no allow line that holds covers :status, :tags"
      assert EntityOperations.get(MutationModule6, ticket.id).status == "closed"
      assert count_edges(MutationModule6, :tags, ticket.id, tag.id) == 0
    end

    test "applies a call's edges when every value it puts loses to a newer edit" do
      ticket = create_ticket("open")
      tag = create_tag("plain")
      newer = ticket.__meta__.revisions.status + 1_000_000

      set_revisions(MutationModule6, ticket.id, %{"status" => newer})

      writes = [
        update_write(MutationModule6, ticket.id, %{"status" => "closed"},
          based_on: %{"status" => ticket.__meta__.revisions.status},
          stamp: newer - 1
        ),
        same_call(edge_write("add_relationship", MutationModule6, ticket.id, "tags", tag.id))
      ]

      assert {:ok, %{"dropped" => %{"0" => %{"status" => "closed"}}}} =
               run(envelope(writes), server())

      assert EntityOperations.get(MutationModule6, ticket.id).status == "open"
      assert count_edges(MutationModule6, :tags, ticket.id, tag.id) == 1
    end

    test "answers a write after a call under its own position" do
      first = create_ticket("open")
      second = create_ticket("open")
      tag = create_tag("plain")
      newer = second.__meta__.revisions.status + 1_000_000

      set_revisions(MutationModule6, second.id, %{"status" => newer})

      writes = [
        update_write(MutationModule6, first.id, %{"status" => "closed"},
          stamp: stamp_above(first)
        ),
        same_call(edge_write("add_relationship", MutationModule6, first.id, "tags", tag.id)),
        update_write(MutationModule6, second.id, %{"status" => "closed"},
          based_on: %{"status" => second.__meta__.revisions.status},
          stamp: newer - 1
        )
      ]

      assert {:ok, %{"status" => "confirmed", "dropped" => dropped, "kept" => kept}} =
               run(envelope(writes), server())

      assert dropped == %{"2" => %{"status" => "closed"}}
      assert Map.keys(kept) == ["2"]
    end

    test "refuses an update naming a row that is not there" do
      write =
        update_write(Module2, Entity.generate_id(), %{"c" => "x"})

      assert run(envelope([write]), server()) == rejected(0, :not_found)
    end

    test "refuses an edge naming a row that is not there" do
      target = create_target()

      write =
        edge_write("add_relationship", Module16, Entity.generate_id(), "secrets", target.id)

      assert run(envelope([write]), server()) == rejected(0, :not_found)
    end

    # A client is never the trusted tier: with nobody signed in the write is evaluated under the
    # anonymous semantics rather than written raw, and Module1 grants an anonymous session no create.
    test "evaluates a create under an anonymous session" do
      write = create_write(MutationModule1, Entity.generate_id(), %{"public" => false})

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server())

      assert reason =~ "not allowed to create Hologram.Test.Fixtures.Mutation.Module1"
    end

    test "refuses a denied write and names the write it refused" do
      landing_id = Entity.generate_id()

      writes = [
        public_write(landing_id),
        create_write(MutationModule1, Entity.generate_id(), %{"public" => false})
      ]

      assert {:ok, %{"status" => "rejected", "write" => 1}} = run(envelope(writes), server())

      # The whole batch rolled back, including the write that had already landed.
      assert EntityOperations.get(MutationModule2, landing_id) == nil
    end

    # A write claiming the operation a user holds was once evaluated against that operation's rules
    # alone, so a reader could delete a row it may only read (#1633). A claim is refused now, and a
    # write is judged by what it does.
    test "refuses a reader's delete claiming the read it may make" do
      owner = create_user("note-owner@example.com")
      reader = create_user("note-reader@example.com")
      row = create_authored(owner, public: true)

      write =
        MutationModule1
        |> delete_write(row.id, based_on: based_on(row), stamp: stamp_above(row))
        |> Map.put("claim", ["authorize", "read"])

      assert run(envelope([write]), server(reader.id)) ==
               {:invalid,
                "write 0: a write claims nothing - the server judges it by what it does"}

      assert EntityOperations.get(MutationModule1, row.id) != nil
    end

    test "refuses a reader's delete" do
      owner = create_user("note-owner-2@example.com")
      reader = create_user("note-reader-2@example.com")
      row = create_authored(owner, public: true)

      write =
        delete_write(MutationModule1, row.id, based_on: based_on(row), stamp: stamp_above(row))

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server(reader.id))

      assert reason =~ "not allowed to delete Hologram.Test.Fixtures.Mutation.Module1"
      assert EntityOperations.get(MutationModule1, row.id) != nil
    end

    test "refuses a reader's update" do
      owner = create_user("note-owner-3@example.com")
      reader = create_user("note-reader-3@example.com")
      row = create_authored(owner, priority: 5, public: true)

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: stamp_above(row)
        )

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server(reader.id))

      assert reason =~ "not allowed to update Hologram.Test.Fixtures.Mutation.Module1"
      assert EntityOperations.get(MutationModule1, row.id).priority == 5
    end

    # An edge changes the row it hangs off, so it is that row's :update, which Mutation.Module4
    # grants nobody.
    test "refuses an edge on a row its session may not update" do
      source = DB.create!(MutationModule4.new())
      target = create_target()

      :ok = EntityOperations.add_relationship(MutationModule4, source.id, :secrets, target.id)

      for op <- ["add_relationship", "delete_relationship"] do
        write = edge_write(op, MutationModule4, source.id, "secrets", target.id)

        assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
                 run(envelope([write]), server())

        assert reason =~ "not allowed to update Hologram.Test.Fixtures.Mutation.Module4"
      end
    end

    # Policy.Module38 lets anyone set a channel's topic while it isn't archived, and only its owner
    # rename it.
    test "lands a browser update of a field a holding line covers" do
      member = create_user("batch-field-member-1@example.com")

      channel =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      write =
        update_write(Channel, channel.id, %{"topic" => "news"}, stamp: stamp_above(channel))

      assert {:ok, %{"status" => "confirmed"}} = run(envelope([write]), server(member.id))
      assert EntityOperations.get(Channel, channel.id).topic == "news"
    end

    test "refuses a browser update of a field no holding line covers" do
      member = create_user("batch-field-member-2@example.com")

      channel =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      write =
        update_write(Channel, channel.id, %{"name" => "mine"}, stamp: stamp_above(channel))

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server(member.id))

      assert reason =~ "no allow line that holds covers :name"
      assert EntityOperations.get(Channel, channel.id).name == "general"
    end

    # Judged by everything it names, before the merge: whether a write is refused doesn't turn on
    # which of its values lose to another writer's.
    test "refuses a browser update naming an uncovered field whose value loses the merge" do
      member = create_user("batch-field-member-3@example.com")

      channel =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      newer = channel.__meta__.revisions.name + 1_000_000

      set_revisions(Channel, channel.id, %{"name" => newer})

      write =
        update_write(Channel, channel.id, %{"name" => "mine", "topic" => "news"},
          based_on: %{"name" => channel.__meta__.revisions.name},
          stamp: newer - 1
        )

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason}} =
               run(envelope([write]), server(member.id))

      assert reason =~ "no allow line that holds covers :name"
      assert EntityOperations.get(Channel, channel.id).topic == nil
    end

    # A write whose every value loses answers with the columns it lost to, which is an answer for
    # whoever may change them.
    test "refuses a browser update whose every value loses, from a user no line lets change it" do
      member = create_user("batch-field-member-4@example.com")

      channel =
        [name: "secret plans"]
        |> Channel.new()
        |> DB.create!()

      newer = channel.__meta__.revisions.name + 1_000_000

      set_revisions(Channel, channel.id, %{"name" => newer})

      write =
        update_write(Channel, channel.id, %{"name" => "x"},
          based_on: %{"name" => channel.__meta__.revisions.name},
          stamp: newer - 1
        )

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason} = answer} =
               run(envelope([write]), server(member.id))

      assert reason =~ "no allow line that holds covers :name"
      refute Map.has_key?(answer, "kept")
    end

    test "refuses a stale browser delete from an anonymous session, answering no row" do
      channel =
        [name: "secret plans"]
        |> Channel.new()
        |> DB.create!()

      newer = channel.__meta__.revisions.name + 1_000_000

      set_revisions(Channel, channel.id, %{"name" => newer})

      write =
        delete_write(Channel, channel.id,
          based_on: %{"name" => channel.__meta__.revisions.name},
          stamp: newer - 1
        )

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason} = answer} =
               run(envelope([write]), server())

      assert reason =~ "not allowed to delete Hologram.Test.Fixtures.Policy.Module38"
      refute Map.has_key?(answer, "kept")
      assert EntityOperations.get(Channel, channel.id) != nil
    end

    test "judges a counter a browser moves by the lines covering it" do
      member = create_user("batch-field-member-6@example.com")

      open =
        [name: "open"]
        |> Channel.new()
        |> DB.create!()

      general =
        [name: "general"]
        |> Channel.new()
        |> DB.create!()

      moved = update_write(Channel, open.id, nil, deltas: %{"sent_count" => 1}, stamp: stamp())

      refused =
        update_write(Channel, general.id, nil, deltas: %{"sent_count" => 1}, stamp: stamp())

      assert {:ok, %{"status" => "confirmed"}} = run(envelope([moved]), server(member.id))
      assert EntityOperations.get(Channel, open.id).sent_count == 1

      assert {:ok, %{"status" => "rejected", "reason" => reason}} =
               run(envelope([refused]), server(member.id))

      assert reason =~ "no allow line that holds covers :sent_count"
    end

    # A dropped delete answers with the whole row it lost to, which is an answer for whoever may
    # delete it - Policy.Module38 lets nobody.
    test "refuses a stale browser delete from a user who may not delete, answering no row" do
      member = create_user("batch-field-member-5@example.com")

      channel =
        [name: "secret plans"]
        |> Channel.new()
        |> DB.create!()

      newer = channel.__meta__.revisions.name + 1_000_000

      set_revisions(Channel, channel.id, %{"name" => newer})

      write =
        delete_write(Channel, channel.id,
          based_on: %{"name" => channel.__meta__.revisions.name},
          stamp: newer - 1
        )

      assert {:ok, %{"status" => "rejected", "write" => 0, "reason" => reason} = answer} =
               run(envelope([write]), server(member.id))

      assert reason =~ "not allowed to delete Hologram.Test.Fixtures.Policy.Module38"
      refute Map.has_key?(answer, "kept")
      assert EntityOperations.get(Channel, channel.id) != nil
    end

    # Module2's roles extend nothing, so under a bare grant_role line each role may grant only
    # itself - a member brings in a member.
    test "lands a role grant under a holder who may grant it" do
      member = create_user("grant-member@example.com")
      user = create_user("grant-user@example.com")
      resource = create_shared()
      replica_id = Entity.generate_id()

      Auth.grant_role(member, :member, resource)

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
               oplog_rows(replica_id)

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
        create_write(MutationModule1, entity_id, %{"author_id" => user.id}),
        grant_write(user.id, %MutationModule1{id: entity_id}, :maintainer)
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
        RoleGrant.derive_id(user.id, MutationModule1, entity_id, :maintainer)

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

      Auth.grant_role(first_member, :member, resource)
      Auth.grant_role(second_member, :member, resource)

      Context.with_actor(first_member.id, fn ->
        Auth.grant_role(user, :member, resource)
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

    # The gate admits a role held on the whole type, so the read rule has to as well, or the answer
    # hands over a row its user may not read.
    test "answers a type-wide holder's repeated grant with a row that holder may read" do
      %{granter: granter, holder: holder, write: write} = repeated_grant()

      assert {:ok, %{"status" => "confirmed", "kept" => kept}} =
               run(envelope([write]), server(holder.id))

      assert kept["0"]["granted_by_id"] == granter.id
      assert Auth.can?(holder.id, :read, EntityOperations.get(RoleGrant, write["id"]))
    end

    test "answers a resent repeated grant with the row as it stands" do
      %{batch: batch, holder: holder, resource: resource, user: user} = answered_repeat()

      Auth.revoke_role(user, :member, resource)

      Context.with_actor(holder.id, fn ->
        Auth.grant_role(user, :member, resource)
      end)

      assert {:ok, %{"status" => "confirmed", "kept" => %{"0" => row}}} =
               run(batch, server(holder.id))

      assert row["granted_by_id"] == holder.id
    end

    test "withholds a resent repeated grant revoked since" do
      %{batch: batch, holder: holder, resource: resource, user: user} = answered_repeat()

      Auth.revoke_role(user, :member, resource)

      assert {:ok, %{"status" => "confirmed", "kept" => kept}} = run(batch, server(holder.id))

      assert kept == %{"0" => %{"$withheld" => true}}
    end

    test "withholds a resent repeated grant its user may no longer read" do
      %{batch: batch, holder: holder} = answered_repeat()

      Auth.revoke_role(holder, :member, PolicyModule2)

      assert {:ok, %{"status" => "confirmed", "kept" => kept}} = run(batch, server(holder.id))

      assert kept == %{"0" => %{"$withheld" => true}}
    end

    # The record keeps no writes of a confirmed batch, so what a resend carries can't be what tells
    # a grant row from any other.
    test "judges a recorded grant whatever writes the resend carries" do
      %{batch: batch, holder: holder} = answered_repeat()

      Auth.revoke_role(holder, :member, PolicyModule2)

      assert {:ok, %{"status" => "confirmed", "kept" => kept}} =
               run(%{batch | "writes" => []}, server(holder.id))

      assert kept == %{"0" => %{"$withheld" => true}}
    end

    test "withholds a resent stale revocation's row its user may no longer read" do
      member = create_user("resend-revoker@example.com")
      user = create_user("resend-regranted@example.com")
      resource = create_shared()

      Auth.grant_role(member, :member, resource)
      Auth.grant_role(user, :member, resource)

      first_row = EntityOperations.get(RoleGrant, grant_id(user.id, resource, :member))

      Auth.revoke_role(user, :member, resource)
      Auth.grant_role(user, :member, resource)

      write =
        revocation_write(user.id, resource, :member,
          based_on: based_on(first_row),
          stamp: first_row.__meta__.revisions.role + 1
        )

      batch = envelope([write])

      assert {:ok, %{"kept" => %{"0" => %{"id" => _id}}}} = run(batch, server(member.id))

      Auth.revoke_role(member, :member, resource)

      assert {:ok, %{"status" => "confirmed", "kept" => kept}} = run(batch, server(member.id))

      assert kept == %{"0" => %{"$withheld" => true}}
    end

    # A revocation that won keeps nothing, so the browser would apply it over a grant made again
    # since, whose revisions can sit below its stamp, with no frame to bring the row back.
    test "answers a resent revocation with its grant only while it's made again and readable" do
      member = create_user("won-revoker@example.com")
      user = create_user("won-revoked@example.com")
      resource = create_shared()

      Auth.grant_role(member, :member, resource)
      Auth.grant_role(user, :member, resource)

      row = EntityOperations.get(RoleGrant, grant_id(user.id, resource, :member))

      write =
        revocation_write(user.id, resource, :member,
          based_on: based_on(row),
          stamp: stamp_above(row)
        )

      batch = envelope([write])

      assert {:ok, %{"status" => "confirmed", "kept" => first_kept}} =
               run(batch, server(member.id))

      assert first_kept == %{}
      assert {:ok, %{"kept" => not_remade}} = run(batch, server(member.id))
      assert not_remade == %{}

      Auth.grant_role(user, :member, resource)

      assert {:ok, %{"kept" => %{"0" => remade}}} = run(batch, server(member.id))
      assert remade["id"] == row.id

      Auth.revoke_role(member, :member, resource)

      assert {:ok, %{"kept" => unreadable}} = run(batch, server(member.id))
      assert unreadable == %{}
    end

    test "answers a doctored resend's revocation only with a grant its sender may read" do
      holder = create_user("doctored-holder@example.com")
      user = create_user("doctored-grantee@example.com")
      readable = create_shared()
      hidden = create_shared()

      Auth.grant_role(holder, :member, readable)
      Auth.grant_role(user, :member, readable)
      Auth.grant_role(user, :member, hidden)

      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(holder.id))

      doctored = %{
        batch
        | "writes" => [
            revocation_write(user.id, readable, :member),
            revocation_write(user.id, hidden, :member)
          ]
      }

      assert {:ok, %{"kept" => kept}} = run(doctored, server(holder.id))

      assert Map.keys(kept) == ["0"]
      assert kept["0"]["id"] == grant_id(user.id, readable, :member)
    end

    # A creator's grant always answers whole, since the create already wrote it, and withholding it
    # would leave the creator without their role until a frame arrives.
    test "answers a resent creator's grant with its row as it stands" do
      user = create_user("resend-creator@example.com")
      entity_id = Entity.generate_id()
      resource = %MutationModule1{id: entity_id}

      writes = [
        create_write(MutationModule1, entity_id, %{"author_id" => user.id}),
        grant_write(user.id, resource, :maintainer)
      ]

      batch = envelope(writes)

      assert {:ok, %{"kept" => %{"1" => %{"granted_by_id" => granted_by_id}}}} =
               run(batch, server(user.id))

      assert granted_by_id == user.id

      Auth.revoke_role(user, :maintainer, resource)
      Auth.grant_role(user, :maintainer, resource)

      assert {:ok, %{"kept" => %{"1" => row}}} = run(batch, server(user.id))

      assert row["id"] == grant_id(user.id, resource, :maintainer)
      assert row["granted_by_id"] == nil
    end

    test "withholds only the grant among what a resent batch kept" do
      %{holder: holder, resource: resource, user: user, write: grant} = repeated_grant()

      row = create_authored(holder, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(MutationModule1, row.id, %{"priority" => newer})

      update =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      batch = envelope([update, grant])

      assert {:ok, %{"kept" => %{"0" => update_kept, "1" => %{"id" => _id}}}} =
               run(batch, server(holder.id))

      Auth.revoke_role(user, :member, resource)

      assert {:ok, %{"kept" => kept}} = run(batch, server(holder.id))

      assert kept == %{"0" => update_kept, "1" => %{"$withheld" => true}}
    end

    test "rolls the batch back on a refused grant" do
      member = create_user("rollback-member@example.com")
      user = create_user("rollback-user@example.com")
      resource = create_shared()
      landing_id = Entity.generate_id()

      Auth.grant_role(member, :member, resource)

      writes = [public_write(landing_id), grant_write(user.id, resource, :admin)]

      assert {:ok, %{"status" => "rejected", "write" => 1}} =
               run(envelope(writes), server(member.id))

      assert EntityOperations.get(MutationModule2, landing_id) == nil
    end

    test "rejects a grant of a role above the holder's own" do
      member = create_user("escalating-member@example.com")
      user = create_user("escalation-user@example.com")
      resource = create_shared()

      Auth.grant_role(member, :member, resource)

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

      Auth.grant_role(member, :member, resource)

      EntityOperations.create_if_absent(%RoleGrant{
        id: Entity.generate_id(),
        entity_id: resource.id,
        entity_type: PolicyModule2,
        role: :member,
        user_id: user.id
      })

      write = grant_write(user.id, resource, :member)

      expected_msg =
        "a role grant for this user, entity and role exists under an id that is not its " <>
          "derivation - every grant row's id is derived from the grant it states"

      assert_error ArgumentError, expected_msg, fn ->
        run(envelope([write]), server(member.id))
      end
    end

    test "rejects a grant to a user that does not exist" do
      member = create_user("granting-to-nobody@example.com")
      resource = create_shared()

      Auth.grant_role(member, :member, resource)

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

      message =
        "type-wide roles are granted only by server code claiming trust: true or running outside a session"

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

      Auth.grant_role(member, :member, resource)
      Auth.grant_role(target, :member, resource)

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

      Auth.grant_role(member, :member, resource)
      Auth.grant_role(leaver, :member, resource)

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

      Auth.grant_role(member, :member, resource)
      Auth.grant_role(user, :member, resource)

      first_row = EntityOperations.get(RoleGrant, grant_id(user.id, resource, :member))
      first_stamp = first_row.__meta__.revisions.role

      Auth.revoke_role(user, :member, resource)
      Auth.grant_role(user, :member, resource)

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

      Auth.grant_role(member, :member, resource)

      write = revocation_write(member.id, resource, :member, stamp: 1)

      message = "a role is revoked only by a signed-in user - nobody is signed in"

      assert run(envelope([write]), server()) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "refuses a stale revocation the acting user may not make without answering the row" do
      member = create_user("probed-again-member@example.com")
      stranger = create_user("stranger@example.com")
      resource = create_shared()

      Auth.grant_role(member, :member, resource)

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

      Auth.grant_role(member, :member, resource)

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
      assert job.attempt == 0
      assert job.error == nil
      assert DateTime.diff(DateTime.utc_now(), job.scheduled_at, :minute) == 0
    end

    # The queue is ordered by the due time, and a browser's clock can be set as far back as it likes.
    test "makes a job due by the server's clock, whatever the writer's stamp says" do
      user = create_user("job-backdater@example.com")
      id = Entity.generate_id()
      backdated = DateTime.to_unix(~U[2000-01-01 00:00:00Z], :millisecond) * 1024

      assert run(
               envelope([create_write(JobModule1, id, %{}, stamp: backdated)]),
               server(user.id)
             ) == {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

      job = EntityOperations.get(JobModule1, id)

      assert job.created_at == ~U[2000-01-01 00:00:00.000000Z]
      assert DateTime.diff(DateTime.utc_now(), job.scheduled_at, :minute) == 0
    end

    test "refuses a job with the batch it rode in" do
      user = create_user("job-loser@example.com")
      job_id = Entity.generate_id()

      writes = [
        create_write(JobModule1, job_id, %{}),
        create_write(MutationModule1, Entity.generate_id(), %{"public" => false})
      ]

      assert {:ok, %{"status" => "rejected", "write" => 1}} =
               run(envelope(writes), server(user.id))

      assert EntityOperations.get(JobModule1, job_id) == nil
    end

    test "refuses a value the declarations refuse" do
      write = create_write(Module19, Entity.generate_id(), %{"code" => "c"})

      assert run(envelope([write]), server()) == rejected(0, %{slug: [:required]})
    end

    test "refuses a duplicate of a unique value" do
      %{slug: "taken"}
      |> Module19.new()
      |> DB.create!()

      write = create_write(Module19, Entity.generate_id(), %{"slug" => "taken"})

      assert run(envelope([write]), server()) == rejected(0, %{slug: [:unique]})
    end

    # The batch is refused whole, naming the write and the key on each of its fields.
    test "refuses a duplicate of a key" do
      %{a: "taken_a", b: "taken_b"}
      |> Module53.new()
      |> DB.create!()

      writes = [
        create_write(Module53, Entity.generate_id(), %{"a" => "free_a", "b" => "free_b"}),
        create_write(Module53, Entity.generate_id(), %{"a" => "taken_a", "b" => "taken_b"})
      ]

      assert run(envelope(writes), server()) ==
               rejected(1, %{a: [unique: [:a, :b]], b: [unique: [:a, :b]]})

      assert length(DB.read(Module53)) == 1
    end

    test "refuses an update that leaves a row repeating a key" do
      %{a: "held_a", b: "held_b"}
      |> Module53.new()
      |> DB.create!()

      row =
        %{a: "held_a", b: "spare_b"}
        |> Module53.new()
        |> DB.create!()

      write =
        update_write(Module53, row.id, %{"b" => "held_b"}, stamp: stamp_above(row))

      assert run(envelope([write]), server()) ==
               rejected(0, %{a: [unique: [:a, :b]], b: [unique: [:a, :b]]})

      assert EntityOperations.get(Module53, row.id).b == "spare_b"
    end

    test "refuses a second reference to the target of a unique to-one" do
      channel =
        %{name: "general"}
        |> Module26.new()
        |> DB.create!()

      %{channel_id: channel.id, summary: "first"}
      |> Module27.new()
      |> DB.create!()

      write =
        create_write(Module27, Entity.generate_id(), %{
          "channel_id" => channel.id,
          "summary" => "second"
        })

      assert run(envelope([write]), server()) == rejected(0, %{channel_id: [:unique]})
    end

    test "refuses a reference naming no row" do
      write =
        create_write(Module3, Entity.generate_id(), %{"c_id" => Entity.generate_id()})

      assert run(envelope([write]), server()) == rejected(0, %{c_id: [:not_found]})
    end

    test "refuses a delete the row's references block" do
      referenced =
        [public: true]
        |> MutationModule2.new()
        |> DB.create!()

      %{b_id: referenced.id}
      |> MutationModule3.new()
      |> DB.create!()

      # The delete has to WIN the merge to reach the executor at all - a client holding the row
      # sends its revisions, and a stamp from the wall clock alone can sit below them.
      write =
        delete_write(MutationModule2, referenced.id,
          based_on: based_on(referenced),
          stamp: stamp_above(referenced)
        )

      assert run(envelope([write]), server()) ==
               rejected(0, %{referenced_by: MutationModule3, relationship: :b})
    end

    test "keeps a batch the evaluator refused, with what it carried and the answer it got" do
      user = create_user("refused@example.com")
      replica_id = Entity.generate_id()
      write = create_write(MutationModule1, Entity.generate_id(), %{"public" => false})
      raw = envelope([write], replica_id: replica_id)

      assert {:ok, %{"status" => "rejected"} = answer} = run(raw, server(user.id))

      assert Record.find(replica_id, 1) == %{actor_id: user.id, result: answer}
      assert record_envelope(replica_id, 1) == raw
    end

    test "answers a refused batch sent again from its record without evaluating it again" do
      user = create_user("resender@example.com")
      id = Entity.generate_id()
      raw = envelope([update_write(MutationModule1, id, %{"priority" => 9})])

      assert run(raw, server(user.id)) == rejected(0, :not_found)

      # The world changed between the two sends - a second evaluation would find the row and land
      # the update - and the answer did not, which is what proves it came from the record.
      create_authored(user, id: id, priority: 5)

      assert run(raw, server(user.id)) == rejected(0, :not_found)
      assert EntityOperations.get(MutationModule1, id).priority == 5
    end

    # A user id no user entity can have - an app's own serial id - is recorded as nobody, a
    # visitor's batch, since the record's actor is a user as the data layer stores one.
    test "lands a batch from a user id no user entity can have, recorded with no actor" do
      replica_id = Entity.generate_id()
      id = Entity.generate_id()
      raw = envelope([public_write(id)], replica_id: replica_id)

      assert {:ok, %{"status" => "confirmed"} = answer} = run(raw, server(7))

      assert EntityOperations.get(MutationModule2, id) != nil
      assert Record.find(replica_id, 1).actor_id == nil
      assert [%{actor_id: nil}] = oplog_rows(replica_id)

      # Sent again, it is answered from its record rather than applied twice.
      assert run(raw, server(7)) == {:ok, answer}
    end

    test "keeps nothing of a batch refused under a user id no user entity can have" do
      replica_id = Entity.generate_id()
      id = Entity.generate_id()
      write = create_write(MutationModule1, id, %{"public" => false})

      message = "not allowed to create Hologram.Test.Fixtures.Mutation.Module1 #{inspect(id)}"

      assert run(envelope([write], replica_id: replica_id), server(7)) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})

      assert Record.find(replica_id, 1) == nil
    end

    test "replays a batch of a user id no user entity can have to a visitor, and not to a user" do
      user = create_user("foreign-replay@example.com")
      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"} = answer} = run(batch, server(7))

      assert run(batch, server(user.id)) == rejected(nil, :forged_client)
      assert run(batch, server()) == {:ok, answer}
    end

    test "records a job create under a user id no user entity can have to run under the rules" do
      id = Entity.generate_id()

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([create_write(JobModule1, id, %{})]), server(7))

      assert %{actor_id: nil, run_as_server: false} = EntityOperations.get(JobModule1, id)
    end

    test "records a signed-out visitor's job create to run under the rules" do
      id = Entity.generate_id()

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([create_write(JobModule1, id, %{})]), server())

      assert %{actor_id: nil, run_as_server: false} = EntityOperations.get(JobModule1, id)
    end

    # A grant naming the session's own user id beside a create would pass as the creator's grant if
    # the id were compared as sent, and then fail its validation, since no user entity has that id.
    test "refuses a creator's grant naming a user id no user entity can have" do
      entity_id = Entity.generate_id()

      writes = [
        create_write(MutationModule5, entity_id, %{}),
        grant_write("abc", %MutationModule5{id: entity_id}, :maintainer)
      ]

      message = "a role is granted only by a signed-in user - nobody is signed in"

      assert run(envelope(writes), server("abc")) ==
               rejected(1, %Hologram.AccessDeniedError{message: message})

      assert EntityOperations.get(MutationModule5, entity_id) == nil
    end

    # Revoking one's own role passes the gate, and the id the revocation names is compared with the
    # session's as the data layer stores a user, so naming the session's own id gets nothing past it.
    test "refuses a revocation naming a user id no user entity can have as its own" do
      resource = create_shared()

      write = revocation_write("abc", resource, :member)

      message = "a role is revoked only by a signed-in user - nobody is signed in"

      assert run(envelope([write]), server("abc")) ==
               rejected(0, %Hologram.AccessDeniedError{message: message})
    end

    test "keeps nothing of a batch refused under an anonymous session" do
      replica_id = Entity.generate_id()
      target_id = Entity.generate_id()
      write = create_write(Module3, Entity.generate_id(), %{"c_id" => target_id})
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
      write = public_write(Entity.generate_id(), stamp: a_year_ahead)

      assert run(envelope([write], replica_id: replica_id), server(user.id)) ==
               rejected(0, :clock)

      assert Record.find(replica_id, 1) == nil
    end

    test "keeps no envelope of a batch that landed" do
      replica_id = Entity.generate_id()
      raw = envelope([public_write(Entity.generate_id())], replica_id: replica_id)

      assert {:ok, %{"status" => "confirmed"}} = run(raw, server())

      assert record_envelope(replica_id, 1) == nil

      assert Record.find(replica_id, 1).result ==
               %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}
    end

    test "leaves no effect of a refused batch" do
      user = create_user("noeffect@example.com")
      replica_id = Entity.generate_id()
      id = Entity.generate_id()
      write = create_write(Module19, id, %{"code" => "c"})

      assert {:ok, %{"status" => "rejected"}} =
               run(envelope([write], replica_id: replica_id), server(user.id))

      # The record is not an effect: it says the batch was refused, and nothing the batch wrote
      # survived it.
      assert Record.find(replica_id, 1) != nil
      assert oplog_rows(replica_id) == []
      assert EntityOperations.get(Module19, id) == nil
    end

    test "refuses a batch whose replica and sequence number belong to another session" do
      sender = create_user("sender@example.com")
      other = create_user("other@example.com")
      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(sender.id))

      assert run(batch, server(other.id)) == rejected(nil, :forged_client)

      # The record still belongs to the session that earned it.
      assert Record.find(batch["replica_id"], 1).actor_id == sender.id
    end

    test "refuses a signed-in session's batch claimed anonymously" do
      sender = create_user("owner@example.com")
      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(sender.id))

      assert run(batch, server()) == rejected(nil, :forged_client)
    end

    test "refuses an anonymous batch claimed by a signed-in session" do
      user = create_user("claimant@example.com")
      batch = envelope([public_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server())

      assert run(batch, server(user.id)) == rejected(nil, :forged_client)
    end

    test "refuses a stamp running ahead of the server's clock and names the write" do
      id = Entity.generate_id()
      a_year_ahead = (System.os_time(:millisecond) + 365 * 86_400_000) * 1024
      replica_id = Entity.generate_id()
      write = public_write(id, stamp: a_year_ahead)

      assert run(envelope([write], replica_id: replica_id), server()) == rejected(0, :clock)

      assert EntityOperations.get(MutationModule2, id) == nil
      assert Record.find(replica_id, 1) == nil
    end

    test "accepts a stamp within the allowance" do
      id = Entity.generate_id()
      four_minutes_ahead = (System.os_time(:millisecond) + 4 * 60_000) * 1024

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([public_write(id, stamp: four_minutes_ahead)]), server())

      assert EntityOperations.get(MutationModule2, id) != nil
    end

    test "refuses a stamp not above the revisions its write was based on" do
      user = create_user("backwards@example.com")
      row = create_authored(user, priority: 5)
      seen = row.__meta__.revisions.priority

      write =
        update_write(MutationModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => seen},
          stamp: seen
        )

      assert run(envelope([write]), server(user.id)) == rejected(0, :clock)
      assert EntityOperations.get(MutationModule1, row.id).priority == 5
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
