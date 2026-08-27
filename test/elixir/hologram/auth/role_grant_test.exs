defmodule Hologram.Auth.RoleGrantTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Auth.RoleGrant
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.NotIncluded
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Role

  describe "__attributes__/0" do
    test "computes the enum value sets from the compiled data model" do
      assert RoleGrant.__attributes__() == [
               {:resource_id, :uuid, [optional: true]},
               {:resource_type, :enum,
                [
                  values: [
                    :test_fixtures_entity_module1,
                    :test_fixtures_entity_module10,
                    :test_fixtures_entity_module11,
                    :test_fixtures_entity_module12,
                    :test_fixtures_entity_module13,
                    :test_fixtures_entity_module14,
                    :test_fixtures_entity_module15,
                    :test_fixtures_entity_module16,
                    :test_fixtures_entity_module17,
                    :test_fixtures_entity_module18,
                    :test_fixtures_entity_module19,
                    :test_fixtures_entity_module2,
                    :test_fixtures_entity_module20,
                    :test_fixtures_entity_module3,
                    :test_fixtures_entity_module4,
                    :test_fixtures_entity_module5,
                    :test_fixtures_entity_module6,
                    :test_fixtures_entity_module7,
                    :test_fixtures_entity_module8,
                    :test_fixtures_entity_module9,
                    :test_fixtures_job_module1,
                    :test_fixtures_job_module2,
                    :test_fixtures_policy_module1,
                    :test_fixtures_policy_module2,
                    :test_fixtures_policy_module3
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

  describe "__relationships__/0" do
    test "targets the designated user entity type" do
      assert RoleGrant.__relationships__() == [
               {:granted_by, Module14, [optional: true]},
               {:user, Module14, []}
             ]
    end
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
               resource_id: nil,
               resource_type: nil,
               role: nil,
               updated_at: nil,
               user: %NotIncluded{relationship: :user},
               user_id: nil
             }
    end

    # The hardcoded map above states the fields but cannot notice one the macro GAINS - it kept
    # passing when every generated entity grew a __meta__ and this hand-written struct did not.
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
end
