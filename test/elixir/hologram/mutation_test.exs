defmodule Hologram.MutationTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Mutation

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
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  # A row whose author is the given user, which `allow :archive, author_id: user_id()` grants that
  # user - the fixtures' one write rule that needs no role grant and holds on a multi-column type.
  defp create_archivable(user, values) do
    PolicyModule1
    |> Entity.new(Keyword.put(values, :author_id, user.id))
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

  defp create_source do
    Module16
    |> Entity.new()
    |> DB.create!()
  end

  defp create_target do
    Module15
    |> Entity.new(token: "t")
    |> DB.create!()
  end

  defp create_user(email) do
    Module14
    |> Entity.new(email: email)
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
      "client_id" => Keyword.get(opts, :client_id, Entity.generate_id()),
      "model_hash" => Keyword.get(opts, :model_hash, Model.hash()),
      "seq" => Keyword.get(opts, :seq, 1),
      "writes" => writes
    }
  end

  # Scoped to one batch by its own mutation_ref: the outbox is shared, and what these ask about is
  # the effects of the batch under test rather than everything the table happens to hold.
  defp outbox_rows(client_id) do
    statement = """
    SELECT "type", "entity_id", "actor_id", "mutation_ref"
    FROM "hologram_system"."outbox"
    WHERE "mutation_ref"->>'client_id' = $1
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [client_id])

    Enum.map(rows, fn [type, entity_id, actor_id, mutation_ref] ->
      %{
        actor_id: Codec.decode(actor_id, :uuid),
        entity_id: Codec.decode(entity_id, :uuid),
        mutation_ref: mutation_ref,
        type: type
      }
    end)
  end

  defp publish_write(id, opts \\ []) do
    claim_opts = Keyword.merge([claim: ["authorize", "publish"]], opts)

    create_write(PolicyModule2, id, %{"public" => true}, claim_opts)
  end

  # The fixtures declaring constraints, unique values and references grant no WRITE operation, so
  # these writes claim :read - a bare `allow :read` grants it to anyone, and what is under test is
  # the value the write carries rather than the claim it makes.
  defp readable_write(entity_type, id, data) do
    create_write(entity_type, id, data, claim: ["authorize", "read"])
  end

  # The batch the record kept for a refusal, or nil when it kept none.
  defp record_envelope(client_id, seq) do
    statement = """
    SELECT "envelope" FROM "hologram_system"."mutation"
    WHERE "client_id" = $1 AND "seq" = $2
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [client_id, seq])

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
    %{
      "op" => "update",
      "type" => inspect(entity_type),
      "id" => id,
      "data" => data,
      "based_on" => Keyword.get(opts, :based_on),
      "claim" => Keyword.get(opts, :claim, ["authorize", "archive"]),
      "stamp" => Keyword.get(opts, :stamp, stamp())
    }
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
               {:ok, %{"status" => "confirmed", "dropped" => %{}}}

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
      client_id = Entity.generate_id()

      run(envelope([publish_write(id)], client_id: client_id, seq: 7), server())

      assert [%{entity_id: ^id, mutation_ref: %{"client_id" => ^client_id, "seq" => 7}}] =
               outbox_rows(client_id)
    end

    test "records the acting user on the effect" do
      user = create_user("publisher@example.com")
      id = Entity.generate_id()
      client_id = Entity.generate_id()

      assert {:ok, %{"status" => "confirmed"}} =
               run(envelope([publish_write(id)], client_id: client_id), server(user.id))

      assert [%{actor_id: actor_id}] = outbox_rows(client_id)
      assert actor_id == user.id
    end

    test "records the applied batch" do
      client_id = Entity.generate_id()

      run(envelope([publish_write(Entity.generate_id())], client_id: client_id, seq: 3), server())

      assert Record.find(client_id, 3).result == %{"status" => "confirmed", "dropped" => %{}}
    end

    test "answers a repeated batch from the record without applying it again" do
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"} = answer} = run(batch, server())
      assert run(batch, server()) == {:ok, answer}

      assert length(outbox_rows(batch["client_id"])) == 1
    end

    test "applies each sequence number of one client on its own" do
      client_id = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([publish_write(first_id)], client_id: client_id, seq: 1), server())
      run(envelope([publish_write(second_id)], client_id: client_id, seq: 2), server())

      assert EntityOperations.get(PolicyModule2, first_id) != nil
      assert EntityOperations.get(PolicyModule2, second_id) != nil

      assert Record.find(client_id, 1) != nil
      assert Record.find(client_id, 2) != nil
    end

    test "applies one sequence number for each client on its own" do
      first_client = Entity.generate_id()
      second_client = Entity.generate_id()
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()

      run(envelope([publish_write(first_id)], client_id: first_client, seq: 1), server())
      run(envelope([publish_write(second_id)], client_id: second_client, seq: 1), server())

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
               {:ok, %{"status" => "confirmed", "dropped" => %{}}}

      reloaded = EntityOperations.get(PolicyModule1, row.id)

      assert reloaded.priority == 9
      assert reloaded.__meta__.revisions.priority == writer_stamp
      assert reloaded.__meta__.revisions.public == row.__meta__.revisions.public
    end

    test "drops a column the row holds a newer revision of and names the value that lost" do
      user = create_user("outrun@example.com")
      row = create_archivable(user, priority: 5)
      newer = row.__meta__.revisions.priority + 1_000_000

      set_revisions(PolicyModule1, row.id, %{"priority" => newer})

      write =
        update_write(PolicyModule1, row.id, %{"priority" => 9},
          based_on: %{"priority" => row.__meta__.revisions.priority},
          stamp: newer - 1
        )

      assert run(envelope([write]), server(user.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{"0" => %{"priority" => 9}}}}

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

    test "applies a delete the writer is based on" do
      user = create_user("remover@example.com")
      row = create_archivable(user, priority: 5)

      write =
        delete_write(PolicyModule1, row.id,
          based_on: based_on(row),
          claim: ["authorize", "archive"],
          stamp: stamp_above(row)
        )

      assert {:ok, %{"status" => "confirmed", "dropped" => %{}}} =
               run(envelope([write]), server(user.id))

      assert EntityOperations.get(PolicyModule1, row.id) == nil
    end

    test "drops a delete when a column moved past it and names every column of the row" do
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

      assert run(envelope([write]), server(user.id)) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{"0" => %{"priority" => nil}}}}

      assert EntityOperations.get(PolicyModule1, row.id) != nil
    end

    test "treats a delete of a row that is not there as done" do
      write = delete_write(Module2, Entity.generate_id())

      assert run(envelope([write]), server()) ==
               {:ok, %{"status" => "confirmed", "dropped" => %{}}}
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

    test "refuses a value the declarations refuse" do
      write = readable_write(Module19, Entity.generate_id(), %{"code" => "c"})

      assert run(envelope([write]), server()) == rejected(0, %{slug: [:required]})
    end

    test "refuses a duplicate of a unique value" do
      Module19
      |> Entity.new(slug: "taken")
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
      required_target =
        Module1
        |> Entity.new()
        |> DB.create!()

      referenced =
        Module2
        |> Entity.new(a: true, c: "x")
        |> DB.create!()

      Module3
      |> Entity.new(b_id: referenced.id, c_id: required_target.id)
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
      client_id = Entity.generate_id()
      write = create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})
      raw = envelope([write], client_id: client_id)

      assert {:ok, %{"status" => "rejected"} = answer} = run(raw, server(user.id))

      assert Record.find(client_id, 1) == %{actor_id: user.id, result: answer}
      assert record_envelope(client_id, 1) == raw
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
      client_id = Entity.generate_id()
      target_id = Entity.generate_id()
      write = readable_write(Module3, Entity.generate_id(), %{"c_id" => target_id})
      raw = envelope([write], client_id: client_id)

      assert run(raw, server()) == rejected(0, %{c_id: [:not_found]})
      assert Record.find(client_id, 1) == nil

      # Nothing kept means no key taken: the same batch sent again is evaluated on its own, and
      # lands once the row its reference names exists.
      Module1
      |> Entity.new(id: target_id)
      |> DB.create!()

      assert {:ok, %{"status" => "confirmed"}} = run(raw, server())
    end

    test "keeps nothing of a batch refused for its clock" do
      user = create_user("fastclock@example.com")
      client_id = Entity.generate_id()
      a_year_ahead = (System.os_time(:millisecond) + 365 * 86_400_000) * 1024
      write = publish_write(Entity.generate_id(), stamp: a_year_ahead)

      assert run(envelope([write], client_id: client_id), server(user.id)) ==
               rejected(0, :clock)

      assert Record.find(client_id, 1) == nil
    end

    test "keeps no envelope of a batch that landed" do
      client_id = Entity.generate_id()
      raw = envelope([publish_write(Entity.generate_id())], client_id: client_id)

      assert {:ok, %{"status" => "confirmed"}} = run(raw, server())

      assert record_envelope(client_id, 1) == nil
      assert Record.find(client_id, 1).result == %{"status" => "confirmed", "dropped" => %{}}
    end

    test "leaves no effect of a refused batch" do
      user = create_user("noeffect@example.com")
      client_id = Entity.generate_id()
      id = Entity.generate_id()
      write = readable_write(Module19, id, %{"code" => "c"})

      assert {:ok, %{"status" => "rejected"}} =
               run(envelope([write], client_id: client_id), server(user.id))

      # The record is not an effect: it says the batch was refused, and nothing the batch wrote
      # survived it.
      assert Record.find(client_id, 1) != nil
      assert outbox_rows(client_id) == []
      assert EntityOperations.get(Module19, id) == nil
    end

    test "refuses a batch whose client and sequence number belong to another session" do
      sender = create_user("sender@example.com")
      other = create_user("other@example.com")
      batch = envelope([publish_write(Entity.generate_id())])

      assert {:ok, %{"status" => "confirmed"}} = run(batch, server(sender.id))

      assert run(batch, server(other.id)) == rejected(nil, :forged_client)

      # The record still belongs to the session that earned it.
      assert Record.find(batch["client_id"], 1).actor_id == sender.id
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
      client_id = Entity.generate_id()
      write = publish_write(id, stamp: a_year_ahead)

      assert run(envelope([write], client_id: client_id), server()) == rejected(0, :clock)

      assert EntityOperations.get(PolicyModule2, id) == nil
      assert Record.find(client_id, 1) == nil
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
      client_id = Entity.generate_id()
      write = create_write(Module2, id, %{"c" => "x"})

      raw = envelope([write], client_id: client_id, model_hash: "other")

      assert run(raw, server()) == rejected(nil, :stale_build)

      assert EntityOperations.get(Module2, id) == nil
      assert Record.find(client_id, 1) == nil
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
