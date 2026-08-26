defmodule Hologram.Mutation.EnvelopeTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Mutation.Envelope

  alias Hologram.Mutation.Envelope
  alias Hologram.Mutation.Write
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  @id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

  defp edge(op, entity_type, relationship, opts \\ []) do
    %{
      "op" => op,
      "type" => inspect(entity_type),
      "id" => Keyword.get(opts, :id, @id),
      "relationship" => relationship,
      "target_id" => Keyword.get(opts, :target_id, @target_id),
      "claim" => Keyword.get(opts, :claim)
    }
  end

  defp create(entity_type, data, opts \\ []) do
    %{
      "op" => "create",
      "type" => inspect(entity_type),
      "id" => Keyword.get(opts, :id, @id),
      "data" => data,
      "claim" => Keyword.get(opts, :claim),
      "stamp" => Keyword.get(opts, :stamp, 5)
    }
  end

  defp delete(entity_type, opts \\ []) do
    %{
      "op" => "delete",
      "type" => inspect(entity_type),
      "id" => Keyword.get(opts, :id, @id),
      "based_on" => Keyword.get(opts, :based_on),
      "claim" => Keyword.get(opts, :claim),
      "stamp" => Keyword.get(opts, :stamp, 5)
    }
  end

  defp raw(writes) do
    %{
      "instance_id" => "i1",
      "client_id" => "c1",
      "model_hash" => "h",
      "seq" => 1,
      "writes" => writes
    }
  end

  defp update(entity_type, data, opts \\ []) do
    %{
      "op" => "update",
      "type" => inspect(entity_type),
      "id" => Keyword.get(opts, :id, @id),
      "data" => data,
      "based_on" => Keyword.get(opts, :based_on),
      "claim" => Keyword.get(opts, :claim),
      "stamp" => Keyword.get(opts, :stamp, 5)
    }
  end

  describe "parse/1" do
    test "parses a header into an envelope" do
      assert parse(raw([])) ==
               {:ok,
                %Envelope{
                  client_id: "c1",
                  instance_id: "i1",
                  model_hash: "h",
                  seq: 1,
                  writes: []
                }}
    end

    test "parses a create into a write" do
      entry = create(Module2, %{"a" => true, "b" => 2, "c" => "x"})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write == %Write{
               based_on: %{},
               claim: nil,
               data: %{a: true, b: 2, c: "x"},
               entity_type: Module2,
               id: @id,
               op: :create,
               relationship: nil,
               stamp: 5,
               target_id: nil
             }
    end

    test "parses an update into a write" do
      entry = update(Module2, %{"c" => "x"}, based_on: %{"c" => 3})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write == %Write{
               based_on: %{c: 3},
               claim: nil,
               data: %{c: "x"},
               entity_type: Module2,
               id: @id,
               op: :update,
               relationship: nil,
               stamp: 5,
               target_id: nil
             }
    end

    test "parses a delete into a write" do
      entry = delete(Module2, based_on: %{"a" => 1, "c" => 3})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write == %Write{
               based_on: %{a: 1, c: 3},
               claim: nil,
               data: %{},
               entity_type: Module2,
               id: @id,
               op: :delete,
               relationship: nil,
               stamp: 5,
               target_id: nil
             }
    end

    test "reads a missing based_on as no revisions" do
      assert {:ok, %Envelope{writes: [write]}} =
               parse(raw([update(Module2, %{"c" => "x"})]))

      assert write.based_on == %{}
    end

    test "reads a based_on through the field a reference is written under" do
      entry = update(Module3, %{"c_id" => @target_id}, based_on: %{"c_id" => 3})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write.based_on == %{c_id: 3}
    end

    test "parses an added edge into a write" do
      entry = edge("add_relationship", Module16, "secrets")

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write == %Write{
               based_on: %{},
               claim: nil,
               data: %{},
               entity_type: Module16,
               id: @id,
               op: :add_relationship,
               relationship: :secrets,
               stamp: nil,
               target_id: @target_id
             }
    end

    test "parses a deleted edge into a write" do
      entry = edge("delete_relationship", Module16, "secrets")

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write.op == :delete_relationship
      assert write.relationship == :secrets
      assert write.target_id == @target_id
    end

    test "parses every write of a batch, in the order they were sent" do
      entries = [
        create(Module2, %{"c" => "first"}),
        create(Module2, %{"c" => "second"}, id: @target_id)
      ]

      assert {:ok, %Envelope{writes: writes}} = parse(raw(entries))

      assert Enum.map(writes, & &1.data) == [%{c: "first"}, %{c: "second"}]
    end

    test "decodes a value by the field's declared type" do
      entry = create(Module4, %{"a" => "2026-07-19", "c" => "y", "d" => 1.5})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write.data == %{a: ~D[2026-07-19], c: :y, d: 1.5}
    end

    test "reads a to-one reference through its id field" do
      entry = create(Module3, %{"c_id" => @target_id})

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write.data == %{c_id: @target_id}
    end

    test "parses a claim naming an operation" do
      entry = create(PolicyModule2, %{"public" => true}, claim: ["authorize", "publish"])

      assert {:ok, %Envelope{writes: [write]}} = parse(raw([entry]))

      assert write.claim == {:authorize, :publish}
    end

    test "refuses an instance id that is not a string" do
      assert parse(%{raw([]) | "instance_id" => 1}) == {:error, "instance_id must be a string"}
    end

    test "refuses a client id that is not a string" do
      assert parse(%{raw([]) | "client_id" => nil}) == {:error, "client_id must be a string"}
    end

    test "refuses a sequence number that is not a non-negative integer" do
      assert parse(%{raw([]) | "seq" => -1}) == {:error, "seq must be a non-negative integer"}
      assert parse(%{raw([]) | "seq" => "1"}) == {:error, "seq must be a non-negative integer"}
    end

    test "refuses a model hash that is not a string" do
      assert parse(%{raw([]) | "model_hash" => 1}) == {:error, "model_hash must be a string"}
    end

    test "refuses writes that are not a list" do
      assert parse(%{raw([]) | "writes" => "nope"}) == {:error, "writes must be a list"}
    end

    test "refuses a write that is not an object" do
      assert parse(raw(["nope"])) == {:error, "write 0: a write must be an object"}
    end

    test "refuses an op this build does not have" do
      entry = %{create(Module2, %{"c" => "x"}) | "op" => "nope"}

      assert parse(raw([entry])) ==
               {:error,
                "write 0: op must be one of create, update, delete, add_relationship, " <>
                  "delete_relationship"}
    end

    test "names the write a refusal came from" do
      entries = [
        create(Module2, %{"c" => "x"}),
        %{create(Module2, %{"c" => "x"}) | "op" => "nope"}
      ]

      assert {:error, "write 1: op must be one of" <> _rest} = parse(raw(entries))
    end

    test "refuses a type that is not a string" do
      entry = %{create(Module2, %{"c" => "x"}) | "type" => 1}

      assert parse(raw([entry])) == {:error, "write 0: type must be a string"}
    end

    test "refuses an entity type this build does not have" do
      entry = %{create(Module2, %{"c" => "x"}) | "type" => "MyApp.NoSuchTypeInThisBuild"}

      assert parse(raw([entry])) ==
               {:error,
                ~s(write 0: type "MyApp.NoSuchTypeInThisBuild" is not an entity type of this build)}
    end

    test "refuses a type naming something this build has but does not store" do
      entry = %{create(Module2, %{"c" => "x"}) | "type" => "Hologram.Mutation.Envelope"}

      assert parse(raw([entry])) ==
               {:error,
                ~s(write 0: type "Hologram.Mutation.Envelope" is not an entity type of this build)}
    end

    test "refuses an id that is not an entity id" do
      entry = create(Module2, %{"c" => "x"}, id: "nope")

      assert parse(raw([entry])) == {:error, "write 0: id must be an entity id"}
    end

    test "refuses data that is not an object" do
      entry = %{create(Module2, %{"c" => "x"}) | "data" => ["c", "x"]}

      assert parse(raw([entry])) == {:error, "write 0: data must be an object"}
    end

    test "refuses a field the entity type does not declare" do
      entry = create(Module2, %{"nope" => 1})

      assert parse(raw([entry])) ==
               {:error,
                ~s[write 0: "nope" is not a field of Hologram.Test.Fixtures.Entity.Module2 a client can write]}
    end

    test "refuses a server-only attribute as a field" do
      entry = create(Module15, %{"token" => "t"})

      assert parse(raw([entry])) ==
               {:error,
                ~s[write 0: "token" is not a field of Hologram.Test.Fixtures.Entity.Module15 a client can write]}
    end

    test "refuses a value that is not the field's spelling" do
      assert parse(raw([create(Module2, %{"b" => "2"})])) ==
               {:error, ~s(write 0: "b" is not a valid integer)}

      assert parse(raw([create(Module4, %{"c" => "no_such_enum_label_in_this_build"})])) ==
               {:error, ~s(write 0: "c" is not a valid enum value)}

      assert parse(raw([create(Module3, %{"c_id" => 1})])) ==
               {:error, ~s(write 0: "c_id" is not a valid entity id)}
    end

    # Membership in the declared values is Entity.validate's to judge, not this layer's: a label
    # naming an atom the build has decodes here and is refused at the write as a value violation,
    # which is what puts it on a form field rather than in a bad request.
    test "reads an enum label outside the declared values as the value it names" do
      assert {:ok, %Envelope{writes: [write]}} = parse(raw([create(Module4, %{"c" => "z"})]))

      assert write.data == %{c: :z}
    end

    test "refuses an update changing nothing" do
      assert parse(raw([update(Module2, %{})])) ==
               {:error, "write 0: an update must change at least one field"}
    end

    test "refuses a delete carrying data" do
      entry =
        Module2
        |> delete()
        |> Map.put("data", %{"c" => "x"})

      assert parse(raw([entry])) == {:error, "write 0: a delete carries no data"}
    end

    test "refuses a based_on that is not an object" do
      entry = update(Module2, %{"c" => "x"}, based_on: [3])

      assert parse(raw([entry])) == {:error, "write 0: based_on must be an object"}
    end

    test "refuses a based_on naming a field a client cannot write" do
      entry = update(Module2, %{"c" => "x"}, based_on: %{"nope" => 3})

      assert parse(raw([entry])) ==
               {:error,
                ~s[write 0: "nope" is not a field of Hologram.Test.Fixtures.Entity.Module2 a client can write]}
    end

    test "refuses a based_on revision that is not a positive integer" do
      assert parse(raw([update(Module2, %{"c" => "x"}, based_on: %{"c" => 0})])) ==
               {:error, ~s(write 0: based_on."c" must be a positive integer)}

      assert parse(raw([update(Module2, %{"c" => "x"}, based_on: %{"c" => "3"})])) ==
               {:error, ~s(write 0: based_on."c" must be a positive integer)}
    end

    test "refuses a relationship that is not a string" do
      entry = %{edge("add_relationship", Module16, "secrets") | "relationship" => 1}

      assert parse(raw([entry])) == {:error, "write 0: relationship must be a string"}
    end

    test "refuses a relationship the entity type does not declare" do
      entry = edge("add_relationship", Module16, "nope")

      assert parse(raw([entry])) ==
               {:error,
                ~s[write 0: "nope" is not a to-many relationship of Hologram.Test.Fixtures.Entity.Module16]}
    end

    test "refuses a to-one relationship as an edge" do
      entry = edge("add_relationship", Module3, "c")

      assert parse(raw([entry])) ==
               {:error,
                ~s[write 0: "c" is not a to-many relationship of Hologram.Test.Fixtures.Entity.Module3]}
    end

    test "refuses a target id that is not an entity id" do
      entry = edge("add_relationship", Module16, "secrets", target_id: "nope")

      assert parse(raw([entry])) == {:error, "write 0: target_id must be an entity id"}
    end

    test "refuses a stamp on an edge" do
      entry =
        "add_relationship"
        |> edge(Module16, "secrets")
        |> Map.put("stamp", 5)

      assert parse(raw([entry])) == {:error, "write 0: an edge carries no stamp"}
    end

    # The whole point of parsing here: a value the model cannot hold is answered as a bad envelope
    # rather than raised out of the applier, which the endpoint would turn into a 500.
    test "refuses an integer too large for the float attribute it names" do
      too_large =
        "9"
        |> String.duplicate(400)
        |> String.to_integer()

      assert parse(raw([create(Module4, %{"d" => too_large})])) ==
               {:error, ~s(write 0: "d" is not a valid float)}
    end

    test "refuses the server's authority as a claim" do
      entry = create(Module2, %{"c" => "x"}, claim: "trust")

      assert parse(raw([entry])) ==
               {:error, "write 0: trust is the server's authority - a client cannot claim it"}
    end

    test "refuses an operation this build does not declare" do
      entry = create(Module2, %{"c" => "x"}, claim: ["authorize", "no_such_operation_declared"])

      assert parse(raw([entry])) ==
               {:error, "write 0: claim names no operation this build declares"}
    end

    test "refuses a claim that is neither null nor an authorize pair" do
      entry = create(Module2, %{"c" => "x"}, claim: ["nope"])

      assert parse(raw([entry])) ==
               {:error, ~s(write 0: claim must be null or ["authorize", operation])}
    end

    test "refuses a stamp that is not a positive integer" do
      assert parse(raw([create(Module2, %{"c" => "x"}, stamp: 0)])) ==
               {:error, "write 0: stamp must be a positive integer"}

      assert parse(raw([create(Module2, %{"c" => "x"}, stamp: nil)])) ==
               {:error, "write 0: stamp must be a positive integer"}
    end
  end
end
