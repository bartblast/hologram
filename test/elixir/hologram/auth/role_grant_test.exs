defmodule Hologram.Auth.RoleGrantTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Entity.Validator
  alias Hologram.Test.Fixtures.Entity
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Job
  alias Hologram.Test.Fixtures.Policy
  alias Hologram.Test.Fixtures.Role

  @other_user_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e13"
  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"
  @entity_type Policy.Module2
  @user_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e12"

  describe "__attributes__/0" do
    test "computes the enum value sets from the compiled data model" do
      assert RoleGrant.__attributes__() == [
               {:entity_id, :uuid, [optional: true]},
               {:entity_type, :enum,
                [
                  values: [
                    Entity.Module1,
                    Entity.Module10,
                    Entity.Module11,
                    Entity.Module12,
                    Entity.Module13,
                    Entity.Module14,
                    Entity.Module15,
                    Entity.Module16,
                    Entity.Module17,
                    Entity.Module18,
                    Entity.Module19,
                    Entity.Module2,
                    Entity.Module20,
                    Entity.Module21,
                    Entity.Module22,
                    Entity.Module23,
                    Entity.Module3,
                    Entity.Module4,
                    Entity.Module5,
                    Entity.Module6,
                    Entity.Module7,
                    Entity.Module8,
                    Entity.Module9,
                    Job.Module1,
                    Job.Module2,
                    Job.Module3,
                    Policy.Module1,
                    Policy.Module2,
                    Policy.Module3,
                    Policy.Module4,
                    Policy.Module5
                  ],
                  optional: true
                ]},
               {:role, :enum,
                [
                  values: [
                    Role.Module1,
                    Role.Module2,
                    :admin,
                    :editor,
                    :maintainer,
                    :member,
                    :owner,
                    :viewer
                  ]
                ]}
             ]
    end
  end

  test "__is_hologram_entity__/0" do
    assert RoleGrant.__is_hologram_entity__()
  end

  test "__policies__/0" do
    assert RoleGrant.__policies__() == []
  end

  test "__policy_sources__/0" do
    assert RoleGrant.__policy_sources__() == []
  end

  describe "__relationships__/0" do
    test "targets the designated user entity type" do
      assert RoleGrant.__relationships__() == [
               {:granted_by, Module14, [optional: true]},
               {:user, Module14, []}
             ]
    end
  end

  test "__role_declarations__/0" do
    assert RoleGrant.__role_declarations__() == []
  end

  test "__roles__/0" do
    assert RoleGrant.__roles__() == []
  end

  describe "__struct__/0" do
    test "defines the fields a generated entity struct would derive" do
      entity = %RoleGrant{}

      assert Map.from_struct(entity) == %{
               __meta__: %Metadata{},
               created_at: nil,
               granted_by: %NotIncluded{relationship: :granted_by},
               granted_by_id: nil,
               id: nil,
               entity_id: nil,
               entity_type: nil,
               role: nil,
               updated_at: nil,
               user: %NotIncluded{relationship: :user},
               user_id: nil
             }
    end

    # The hardcoded map above states the fields but cannot notice one the macro GAINS - it kept
    # passing when every generated entity grew a __meta__ and this hand-written struct did not.
    # Module1 declares nothing, so its exported functions are exactly the set use Hologram.Entity
    # owns. The struct-field twin below cannot see a FUNCTION the macro gains, which is how
    # __meta__ slipped in once already - this one binds every future addition.
    test "exports every function the entity macro puts on an entity that declares nothing" do
      macro_functions = Module1.__info__(:functions)
      own_functions = RoleGrant.__info__(:functions)

      missing = macro_functions -- own_functions

      assert missing == []
    end

    # Module1 declares nothing, so its fields are exactly the set use Hologram.Entity owns.
    test "carries every field the entity macro puts on an entity that declares nothing" do
      macro_fields =
        %Module1{}
        |> Map.from_struct()
        |> Map.keys()
        |> MapSet.new()

      own_fields =
        %RoleGrant{}
        |> Map.from_struct()
        |> Map.keys()
        |> MapSet.new()

      assert MapSet.difference(macro_fields, own_fields) == MapSet.new()
    end
  end

  test "__system_attributes__/0" do
    assert RoleGrant.__system_attributes__() == [
             {:created_at, :datetime, []},
             {:id, :uuid, []},
             {:updated_at, :datetime, []}
           ]
  end

  describe "derive_id/4" do
    test "answers the same id for the same grant" do
      first = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)
      second = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)

      assert first == second
    end

    test "answers a different id for a different role on the same resource" do
      member_id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)
      admin_id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :admin)

      assert member_id != admin_id
    end

    test "answers a different id for the same role held by a different user" do
      first = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)
      second = RoleGrant.derive_id(@other_user_id, @entity_type, @entity_id, :member)

      assert first != second
    end

    # Asked of the validator rather than of a regex written here, so the two cannot drift: the
    # derivation has to answer something every other entity id would be accepted as.
    test "answers an id the entity id validator accepts" do
      id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)

      assert Validator.attribute_value_valid?(id, :uuid)
    end

    test "answers a version 5 id under the RFC variant" do
      id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)

      <<_time_low_and_mid::binary-size(14), version::binary-size(1), _rest::binary-size(4),
        variant::binary-size(1), _tail::binary>> = id

      assert version == "5"
      assert variant in ["8", "9", "a", "b"]
    end

    test "derives a type-wide grant, which names no entity id" do
      type_wide_id = RoleGrant.derive_id(@user_id, @entity_type, nil, :member)
      instance_id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)

      assert Validator.attribute_value_valid?(type_wide_id, :uuid)
      assert type_wide_id != instance_id
    end

    test "derives a global grant, which names neither and whose role is a module" do
      global_id = RoleGrant.derive_id(@user_id, nil, nil, Role.Module1)

      assert Validator.attribute_value_valid?(global_id, :uuid)
    end

    # The vector the client's hand-written twin asserts against - deriveGrantId in
    # assets/js/elixir/hologram/auth.mjs answers these same two strings from these same inputs,
    # which is what keeps the pair from drifting. Both were cross-checked against a reference
    # UUIDv5 implementation, so either side can be rewritten against the standard alone.
    test "answers the pinned vectors the client twin is held to" do
      instance_id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :member)
      global_id = RoleGrant.derive_id(@user_id, nil, nil, Role.Module1)
      # A role name outside ASCII: the name is hashed as UTF-8 bytes, which a twin reading
      # UTF-16 code units would get wrong while passing the two vectors above.
      accented_id = RoleGrant.derive_id(@user_id, @entity_type, @entity_id, :café)

      assert instance_id == "2c56252b-0c90-5cd9-b15d-91c5e5bf968e"
      assert global_id == "f0fd8d8d-3d3f-5dd8-9027-2441a5a93040"
      assert accented_id == "84121d8c-09a3-57fa-96e3-bd966906ce20"
    end
  end

  describe "entity_type/1" do
    test "answers the entity type whose resource type label it is given" do
      assert RoleGrant.entity_type(Module14) == Module14
    end

    test "answers nil for a label naming no entity type of this build" do
      assert RoleGrant.entity_type(NoSuchEntityTypeInThisBuild) == nil
    end

    # The store's own type is left out of its scope enum: a grant is never held on a grant row.
    test "answers nil for the role grant entity type itself" do
      assert RoleGrant.entity_type(RoleGrant) == nil
    end
  end

  describe "identity_columns/0" do
    # Read from the derived mapping rather than from the mapper's source, so this binds what the
    # database is actually given: the store's unique index is over the identity and nothing else.
    # The applier reads a present grant back by the id these columns derive, which is right only
    # while a conflict on the index IS a conflict on the derived primary key.
    test "names exactly the columns the grant store's unique index is over" do
      %{columns: index_columns} = DB.mapping()[RoleGrant].indexes["hologram_role_grant_$uidx"]

      assert index_columns == RoleGrant.identity_columns()
    end
  end

  describe "new/1" do
    test "refuses construction the way the engine does" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error ArgumentError, expected_msg, fn ->
        RoleGrant.new()
      end
    end
  end

  describe "t/0" do
    # Module1 declares nothing, so its field types are exactly the set use Hologram.Entity owns.
    # The two parity tests above cannot see a TYPE the macro gains, which is the same blind spot
    # that let __meta__ slip in once already.
    test "types every field the entity macro types on an entity that declares nothing" do
      macro_types = struct_field_types(Module1)

      own_types = struct_field_types(RoleGrant)

      assert Map.take(own_types, Map.keys(macro_types)) == macro_types
    end
  end
end
