defmodule Hologram.Mutation.WriteTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Mutation.Write

  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Mutation.Write
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2

  @actor_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e13"
  @granter_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e11"
  @id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"
  @user_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e12"

  defp grant_write do
    %Write{
      data: %{
        granted_by_id: @granter_id,
        entity_id: @target_id,
        resource_type: PolicyModule2,
        role: :member,
        user_id: @user_id
      },
      entity_type: RoleGrant,
      id: @id,
      op: :create,
      stamp: 5
    }
  end

  defp revocation_write do
    %Write{
      based_on: %{role: 3},
      data: %{
        entity_id: @target_id,
        resource_type: PolicyModule2,
        role: :member,
        user_id: @user_id
      },
      entity_type: RoleGrant,
      id: @id,
      op: :delete,
      stamp: 5
    }
  end

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

    test "records an update's changes as put ops on the struct and on its metadata" do
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
                 attribute_ops: %{c: {:put, "x"}},
                 claim: {:authorize, :update},
                 revisions: %{c: 3},
                 stamp: 5
               },
               a: false,
               b: nil,
               c: "x",
               created_at: nil,
               id: @id,
               updated_at: nil
             }
    end

    test "records an update's deltas as increment ops on its metadata alone" do
      write = %Write{deltas: %{count: 2}, entity_type: Module10, id: @id, op: :update, stamp: 5}

      entity = to_entity(write)

      assert entity.__meta__ == %Metadata{
               attribute_ops: %{count: {:increment, 2}},
               claim: {:authorize, :update},
               stamp: 5
             }

      assert entity.count == nil
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
               a: false,
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

    # The write carries a granter of its own and it is overwritten: a browser says which role it
    # is handing to whom, never who is handing it.
    test "builds a role grant with the acting user as its granter" do
      entity = Context.with_actor(@actor_id, fn -> to_entity(grant_write()) end)

      assert entity == %RoleGrant{
               __meta__: %Metadata{stamp: 5},
               created_at: nil,
               granted_by: %NotIncluded{relationship: :granted_by},
               granted_by_id: @actor_id,
               id: @id,
               entity_id: @target_id,
               resource_type: PolicyModule2,
               role: :member,
               updated_at: nil,
               user: %NotIncluded{relationship: :user},
               user_id: @user_id
             }
    end

    test "leaves the granter unset with no acting user" do
      entity = Context.with_actor(nil, fn -> to_entity(grant_write()) end)

      assert entity.granted_by_id == nil
    end

    # The struct the revocation gate is asked about: the grant the write states, under the write's
    # id, with the revisions it was based on - a granter is nothing a revocation says.
    test "builds a role grant from the grant a revocation carries" do
      entity = Context.with_actor(@actor_id, fn -> to_entity(revocation_write()) end)

      assert entity == %RoleGrant{
               __meta__: %Metadata{revisions: %{role: 3}, stamp: 5},
               created_at: nil,
               granted_by: %NotIncluded{relationship: :granted_by},
               granted_by_id: nil,
               id: @id,
               entity_id: @target_id,
               resource_type: PolicyModule2,
               role: :member,
               updated_at: nil,
               user: %NotIncluded{relationship: :user},
               user_id: @user_id
             }
    end
  end
end
