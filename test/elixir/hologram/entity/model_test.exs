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

  describe "fold/2" do
    test "applies the ops in order" do
      ops = [
        %{op: :create_entity, entity: MyApp.Draft, line: 3},
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 4},
        %{op: :create_entity, entity: MyApp.Draft, line: 5}
      ]

      assert fold(empty(), ops) == %{
               entities: %{
                 MyApp.Draft => %{attributes: [], relationships: [], roles: []},
                 MyApp.Sketch => %{attributes: [], relationships: [], roles: []}
               },
               roles: %{}
             }
    end

    test "creates an entity type with no declarations" do
      ops = [%{op: :create_entity, entity: MyApp.Task, line: 3}]

      assert fold(empty(), ops) == %{
               entities: %{MyApp.Task => %{attributes: [], relationships: [], roles: []}},
               roles: %{}
             }
    end

    test "deletes an entity type" do
      model = fold(empty(), [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ops = [%{op: :delete_entity, entity: MyApp.Task, line: 4}]

      assert fold(model, ops) == empty()
    end

    test "renames an entity type" do
      model = fold(empty(), [%{op: :create_entity, entity: MyApp.Draft, line: 3}])
      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 4}]

      assert fold(model, ops) == %{
               entities: %{MyApp.Sketch => %{attributes: [], relationships: [], roles: []}},
               roles: %{}
             }
    end

    test "points the relationships targeting a renamed entity type at its new name" do
      model = %{
        entities: %{
          MyApp.Draft => %{attributes: [], relationships: [], roles: []},
          MyApp.Task => %{
            attributes: [],
            relationships: [
              {:draft, MyApp.Draft, []},
              {:drafts, [MyApp.Draft], []},
              {:other, MyApp.Other, []}
            ],
            roles: []
          }
        },
        roles: %{}
      }

      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3}]

      assert fold(model, ops) == %{
               entities: %{
                 MyApp.Sketch => %{attributes: [], relationships: [], roles: []},
                 MyApp.Task => %{
                   attributes: [],
                   relationships: [
                     {:draft, MyApp.Sketch, []},
                     {:drafts, [MyApp.Sketch], []},
                     {:other, MyApp.Other, []}
                   ],
                   roles: []
                 }
               },
               roles: %{}
             }
    end

    test "raises when creating an entity type that already exists" do
      model = fold(empty(), [%{op: :create_entity, entity: MyApp.Task, line: 3}])
      ops = [%{op: :create_entity, entity: MyApp.Task, line: 4}]

      expected_msg =
        "entity MyApp.Task already exists at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when deleting an entity type that does not exist" do
      ops = [%{op: :delete_entity, entity: MyApp.Task, line: 3}]

      expected_msg = "no such entity MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(empty(), ops) end
    end

    test "raises when renaming an entity type that does not exist" do
      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3}]

      expected_msg = "no such entity MyApp.Draft at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(empty(), ops) end
    end

    test "raises when renaming an entity type to a name that already exists" do
      model =
        fold(empty(), [
          %{op: :create_entity, entity: MyApp.Draft, line: 3},
          %{op: :create_entity, entity: MyApp.Sketch, line: 4}
        ])

      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 5}]

      expected_msg = "entity MyApp.Sketch already exists at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises on an unresolved draft op" do
      ops = [%{op: :resolve!, kind: :attributes, payload: [], line: 7}]

      expected_msg =
        "unresolved resolve! op at line 7 - " <>
          "a draft migration is resolved by hand before it can be replayed"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(empty(), ops) end
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
