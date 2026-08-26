defmodule Hologram.Mutation.WriteTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Mutation.Write

  alias Hologram.Entity.Metadata
  alias Hologram.Mutation.Write
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module2

  @id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

  describe "to_entity/1" do
    test "builds a create as a new struct with its declared defaults filled" do
      write = %Write{
        data: %{c: "x"},
        entity_type: Module2,
        id: @id,
        op: :create,
        stamp: 5
      }

      assert to_entity(write) == %Module2{
               __meta__: %Metadata{claim: {:authorize, :create}, stamp: 5},
               a: false,
               b: nil,
               c: "x",
               created_at: nil,
               id: @id,
               updated_at: nil
             }
    end

    test "records an update's changes on the struct and on its metadata" do
      write = %Write{
        based_on: %{c: 3},
        data: %{c: "x"},
        entity_type: Module2,
        id: @id,
        op: :update,
        stamp: 5
      }

      assert to_entity(write) == %Module2{
               __meta__: %Metadata{
                 attribute_changes: %{c: "x"},
                 claim: {:authorize, :update},
                 revisions: %{c: 3},
                 stamp: 5
               },
               a: nil,
               b: nil,
               c: "x",
               created_at: nil,
               id: @id,
               updated_at: nil
             }
    end

    test "records a delete with the revisions it was based on" do
      write = %Write{
        based_on: %{a: 1, c: 3},
        entity_type: Module2,
        id: @id,
        op: :delete,
        stamp: 5
      }

      assert to_entity(write) == %Module2{
               __meta__: %Metadata{
                 claim: {:authorize, :delete},
                 revisions: %{a: 1, c: 3},
                 stamp: 5
               },
               a: nil,
               b: nil,
               c: nil,
               created_at: nil,
               id: @id,
               updated_at: nil
             }
    end

    test "records an added edge" do
      write = %Write{
        entity_type: Module16,
        id: @id,
        op: :add_relationship,
        relationship: :secrets,
        target_id: @target_id
      }

      assert to_entity(write) == %Module16{
               __meta__: %Metadata{
                 claim: {:authorize, :update},
                 relationship_ops: %{{:secrets, @target_id} => :add}
               },
               created_at: nil,
               id: @id,
               name: nil,
               secrets: %Hologram.Entity.NotIncluded{relationship: :secrets},
               updated_at: nil
             }
    end

    test "records a deleted edge" do
      write = %Write{
        entity_type: Module16,
        id: @id,
        op: :delete_relationship,
        relationship: :secrets,
        target_id: @target_id
      }

      assert to_entity(write).__meta__ == %Metadata{
               claim: {:authorize, :update},
               relationship_ops: %{{:secrets, @target_id} => :delete}
             }
    end

    test "keeps the claim the write makes" do
      write = %Write{
        claim: {:authorize, :publish},
        data: %{c: "x"},
        entity_type: Module2,
        id: @id,
        op: :create,
        stamp: 5
      }

      assert to_entity(write).__meta__.claim == {:authorize, :publish}
    end

    # A client is never the trusted tier: a server-side verb writes raw when nobody is acting,
    # and a batch instead evaluates the verb's own operation under whatever authority there is.
    test "gives a write claiming nothing the operation of the verb it is" do
      create = %Write{data: %{label: "x"}, entity_type: Module15, id: @id, op: :create, stamp: 5}

      added_edge = %Write{
        entity_type: Module16,
        id: @id,
        op: :add_relationship,
        relationship: :secrets,
        target_id: @target_id
      }

      writes = [
        create,
        %{create | op: :update},
        %{create | op: :delete},
        added_edge,
        %{added_edge | op: :delete_relationship}
      ]

      assert Enum.map(writes, &to_entity(&1).__meta__.claim) == [
               {:authorize, :create},
               {:authorize, :update},
               {:authorize, :delete},
               {:authorize, :update},
               {:authorize, :update}
             ]
    end
  end
end
