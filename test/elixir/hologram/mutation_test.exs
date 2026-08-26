defmodule Hologram.MutationTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Mutation

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Record
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

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

  defp envelope(writes, opts \\ []) do
    %{
      "instance_id" => "i1",
      "client_id" => Keyword.get(opts, :client_id, Entity.generate_id()),
      "model_hash" => Keyword.get(opts, :model_hash, Model.hash()),
      "seq" => Keyword.get(opts, :seq, 1),
      "writes" => writes
    }
  end

  defp mutation_row_count do
    {:ok, %Postgrex.Result{rows: [[count]]}} =
      Connection.query(~s|SELECT count(*) FROM "hologram_system"."mutation"|)

    count
  end

  defp outbox_rows do
    statement = """
    SELECT "type", "entity_id", "actor_id", "mutation_ref"
    FROM "hologram_system"."outbox"
    ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

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

  defp server(user_id \\ nil), do: %Server{user_id: user_id}

  defp stamp, do: System.os_time(:millisecond) * 1024

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

      assert {:ok, _result} = run(envelope(writes), server())

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

      assert [%{mutation_ref: %{"client_id" => ^client_id, "seq" => 7}}] = outbox_rows()
    end

    test "records the acting user on the effect" do
      user = create_user("publisher@example.com")
      id = Entity.generate_id()

      assert {:ok, _result} = run(envelope([publish_write(id)]), server(user.id))

      assert [effect] = Enum.filter(outbox_rows(), &(&1.entity_id == id))
      assert effect.actor_id == user.id
    end

    test "records the applied batch" do
      client_id = Entity.generate_id()

      run(envelope([publish_write(Entity.generate_id())], client_id: client_id, seq: 3), server())

      assert Record.result(client_id, 3) == %{"status" => "confirmed", "dropped" => %{}}
    end

    # A client is never the trusted tier: with nobody signed in the write is evaluated under the
    # anonymous semantics rather than written raw, and Module1 grants :create to nobody.
    # TODO: D3 turns this raise into {:rejected, 0, %AccessDeniedError{}} - rewrite it there.
    test "evaluates an unclaimed create under an anonymous session" do
      write = create_write(PolicyModule1, Entity.generate_id(), %{"public" => false})

      assert_error Hologram.AccessDeniedError,
                   ~r/^not allowed to create Hologram\.Test\.Fixtures\.Policy\.Module1 /,
                   fn -> run(envelope([write]), server()) end
    end

    test "refuses a batch built against another model" do
      id = Entity.generate_id()
      write = create_write(Module2, id, %{"c" => "x"})

      assert run(envelope([write], model_hash: "other"), server()) ==
               {:rejected, nil, :stale_build}

      assert EntityOperations.get(Module2, id) == nil
      assert mutation_row_count() == 0
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
