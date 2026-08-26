defmodule Hologram.Mutation.EnvelopeTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Mutation.Envelope

  alias Hologram.Mutation.Envelope
  alias Hologram.Mutation.Write
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  @id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

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

  defp raw(writes) do
    %{
      "instance_id" => "i1",
      "client_id" => "c1",
      "model_hash" => "h",
      "seq" => 1,
      "writes" => writes
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
