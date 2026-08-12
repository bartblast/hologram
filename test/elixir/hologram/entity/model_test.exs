defmodule Hologram.Entity.ModelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Model

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Role.Module1, as: RoleModule1
  alias Hologram.Test.Fixtures.Role.Module2, as: RoleModule2

  describe "empty/0" do
    test "returns a model with no entity types and no global roles" do
      assert empty() == %{entities: %{}, roles: %{}}
    end
  end

  describe "from_modules/2" do
    test "derives an entry for an entity type without declarations" do
      assert from_modules([Module1]) == %{
               entities: %{Module1 => %{attributes: [], relationships: [], roles: []}},
               roles: %{}
             }
    end

    test "derives attributes sorted by name" do
      assert from_modules([Module2]) == %{
               entities: %{
                 Module2 => %{
                   attributes: [
                     {:a, :boolean, [default: false]},
                     {:b, :integer, [optional: true]},
                     {:c, :string, []}
                   ],
                   relationships: [],
                   roles: []
                 }
               },
               roles: %{}
             }
    end

    test "derives relationships and roles with opts sorted by key" do
      assert from_modules([Module13]) == %{
               entities: %{
                 Module13 => %{
                   attributes: [
                     {:priority, :integer, [optional: true]},
                     {:public, :boolean, [default: false]},
                     {:title, :string, []}
                   ],
                   relationships: [{:parent, Module1, [optional: true]}],
                   roles: [{:editor, []}, {:owner, [creator: true, extends: :editor]}]
                 }
               },
               roles: %{}
             }
    end

    test "derives global role entries from the given role modules" do
      assert from_modules([], [RoleModule1, RoleModule2]) == %{
               entities: %{},
               roles: %{
                 RoleModule1 => %{extends: RoleModule1.__extends__()},
                 RoleModule2 => %{extends: RoleModule2.__extends__()}
               }
             }
    end

    test "leaves out the role grant store, which is derived rather than declared" do
      assert from_modules([Module1, RoleGrant]) == from_modules([Module1])
    end

    test "returns equal terms regardless of the given module order" do
      assert from_modules([Module13, Module2]) == from_modules([Module2, Module13])
    end
  end
end
