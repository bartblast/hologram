defmodule Hologram.Entity.ModelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Model

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Role.Module1, as: RoleModule1
  alias Hologram.Test.Fixtures.Role.Module2, as: RoleModule2

  defp task_model(entry_overrides) do
    entry =
      Map.merge(
        %{attributes: [], relationships: [], roles: []},
        entry_overrides
      )

    %{entities: %{MyApp.Task => entry}, roles: %{}}
  end

  describe "empty/0" do
    test "returns a model with no entity types and no global roles" do
      assert empty() == %{entities: %{}, roles: %{}}
    end
  end

  describe "fold/2" do
    test "adds attributes, relationships, and roles to their entity type" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: [], line: 4},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [optional: true],
          line: 5
        },
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [],
          line: 6
        },
        %{op: :add_role, entity: MyApp.Task, name: :editor, opts: [], line: 7}
      ]

      assert fold(empty(), ops) ==
               task_model(%{
                 attributes: [{:priority, :integer, [optional: true]}, {:title, :string, []}],
                 relationships: [{:author, MyApp.User, []}],
                 roles: [{:editor, []}]
               })
    end

    test "changes an attribute's type and options as deltas" do
      model = task_model(%{attributes: [{:estimate, :integer, [min: 0]}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :estimate,
          changes: [type: :float, max: 10],
          line: 3
        }
      ]

      assert fold(model, ops) ==
               task_model(%{attributes: [{:estimate, :float, [max: 10, min: 0]}]})
    end

    test "removes attribute options spelled as their neutral values" do
      model = task_model(%{attributes: [{:priority, :integer, [default: 0, optional: true]}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :priority,
          changes: [default: nil, optional: false],
          line: 3
        }
      ]

      assert fold(model, ops) == task_model(%{attributes: [{:priority, :integer, []}]})
    end

    test "changes an attribute to :enum with its initial values" do
      model = task_model(%{attributes: [{:status, :string, []}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :status,
          changes: [type: :enum, values: [:todo, :done]],
          line: 3
        }
      ]

      assert fold(model, ops) ==
               task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})
    end

    test "drops the values when an attribute leaves :enum" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :status,
          changes: [type: :string],
          line: 3
        }
      ]

      assert fold(model, ops) == task_model(%{attributes: [{:status, :string, []}]})
    end

    test "changes a relationship's target and options as deltas" do
      model = task_model(%{relationships: [{:tags, [MyApp.Tag], []}]})

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :tags,
          changes: [type: [MyApp.Label], optional: true],
          line: 3
        }
      ]

      assert fold(model, ops) ==
               task_model(%{relationships: [{:tags, [MyApp.Label], [optional: true]}]})
    end

    test "changes a role's options as deltas" do
      model = task_model(%{roles: [{:owner, [extends: :editor]}]})

      ops = [
        %{op: :change_role, entity: MyApp.Task, name: :owner, changes: [creator: true], line: 3}
      ]

      assert fold(model, ops) ==
               task_model(%{roles: [{:owner, [creator: true, extends: :editor]}]})
    end

    test "renames attributes, relationships, and roles" do
      model =
        task_model(%{
          attributes: [{:name, :string, []}],
          relationships: [{:author, MyApp.User, []}],
          roles: [{:moderator, []}]
        })

      ops = [
        %{op: :rename_attribute, entity: MyApp.Task, from: :name, to: :title, line: 3},
        %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator, line: 4},
        %{op: :rename_role, entity: MyApp.Task, from: :moderator, to: :maintainer, line: 5}
      ]

      assert fold(model, ops) ==
               task_model(%{
                 attributes: [{:title, :string, []}],
                 relationships: [{:creator, MyApp.User, []}],
                 roles: [{:maintainer, []}]
               })
    end

    test "deletes attributes, relationships, and roles" do
      model =
        task_model(%{
          attributes: [{:legacy, :string, []}, {:title, :string, []}],
          relationships: [{:author, MyApp.User, []}],
          roles: [{:viewer, []}]
        })

      ops = [
        %{op: :delete_attribute, entity: MyApp.Task, name: :legacy, line: 3},
        %{op: :delete_relationship, entity: MyApp.Task, name: :author, line: 4},
        %{op: :delete_role, entity: MyApp.Task, name: :viewer, line: 5}
      ]

      assert fold(model, ops) == task_model(%{attributes: [{:title, :string, []}]})
    end

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

    test "raises when adding a member that already exists" do
      model = task_model(%{attributes: [{:title, :string, []}]})

      ops = [
        %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: [], line: 3}
      ]

      expected_msg =
        "attribute :title already exists on MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when changing a member that does not exist" do
      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [type: :string],
          line: 3
        }
      ]

      expected_msg = "no such attribute :title on MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn ->
        fold(task_model(%{}), ops)
      end
    end

    test "raises when changing an attribute to :enum without values" do
      model = task_model(%{attributes: [{:status, :string, []}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :status,
          changes: [type: :enum],
          line: 3
        }
      ]

      expected_msg = "changing attribute :status on MyApp.Task to :enum requires values:"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when a change carries values for an enum attribute" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :status,
          changes: [values: [:todo, :completed]],
          line: 3
        }
      ]

      expected_msg =
        "enum values change through add_enum_value, rename_enum_value, " <>
          "delete_enum_value, or reorder_enum_values - change_attribute never " <>
          "carries values:"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when deleting a member that does not exist" do
      ops = [%{op: :delete_role, entity: MyApp.Task, name: :viewer, line: 3}]

      expected_msg = "no such role :viewer on MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn ->
        fold(task_model(%{}), ops)
      end
    end

    test "raises when renaming a member that does not exist" do
      ops = [
        %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator, line: 3}
      ]

      expected_msg =
        "no such relationship :author on MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn ->
        fold(task_model(%{}), ops)
      end
    end

    test "raises when renaming a member to a name that already exists" do
      model = task_model(%{attributes: [{:name, :string, []}, {:title, :string, []}]})

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :name, to: :title, line: 3}]

      expected_msg =
        "attribute :title already exists on MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
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

    test "normalizes neutral option values to absence" do
      defmodule InlineNeutralOptsFixture do
        use Hologram.Entity

        attribute :a, :integer, optional: false
        attribute :b, :boolean, default: false
      end

      assert from_modules([InlineNeutralOptsFixture]) == %{
               entities: %{
                 InlineNeutralOptsFixture => %{
                   attributes: [{:a, :integer, []}, {:b, :boolean, [default: false]}],
                   relationships: [],
                   roles: []
                 }
               },
               roles: %{}
             }
    end

    test "returns equal terms regardless of the given module order" do
      assert from_modules([Module13, Module2]) == from_modules([Module2, Module13])
    end
  end
end
