defmodule Hologram.Entity.ModelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Model

  alias Hologram.Auth.RoleGrant
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Role.Module1, as: RoleModule1
  alias Hologram.Test.Fixtures.Role.Module2, as: RoleModule2

  defp task_model(entry_overrides) do
    entry =
      Map.merge(
        %{attributes: [], relationships: [], roles: []},
        entry_overrides
      )

    %{entities: %{MyApp.Task => entry}, roles: %{}, user_entity: nil}
  end

  describe "empty/0" do
    test "returns a model with no entity types, no global roles, and no designated user entity type" do
      assert empty() == %{entities: %{}, roles: %{}, user_entity: nil}
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

    test "adds enum values at the given positions" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :archived,
          opts: [],
          line: 3
        },
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :draft,
          opts: [before: :todo],
          line: 4
        },
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :doing,
          opts: [after: :todo],
          line: 5
        }
      ]

      assert fold(model, ops) ==
               task_model(%{
                 attributes: [
                   {:status, :enum, [values: [:draft, :todo, :doing, :done, :archived]]}
                 ]
               })
    end

    test "adds, renames, and deletes global roles" do
      ops = [
        %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 3},
        %{op: :add_role, role: MyApp.Roles.Owner, opts: [extends: MyApp.Roles.Admin], line: 4},
        %{op: :add_role, role: MyApp.Roles.Support, opts: [], line: 5},
        %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Manager, line: 6},
        %{op: :delete_role, role: MyApp.Roles.Support, line: 7}
      ]

      assert fold(empty(), ops) == %{
               entities: %{},
               roles: %{
                 MyApp.Roles.Manager => %{extends: []},
                 MyApp.Roles.Owner => %{extends: [MyApp.Roles.Manager]}
               },
               user_entity: nil
             }
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

    test "changes a global role's extends as deltas" do
      model =
        fold(empty(), [
          %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 3},
          %{op: :add_role, role: MyApp.Roles.Owner, opts: [], line: 4}
        ])

      change_ops = [
        %{
          op: :change_role,
          role: MyApp.Roles.Owner,
          changes: [extends: MyApp.Roles.Admin],
          line: 5
        }
      ]

      removal_ops = [
        %{op: :change_role, role: MyApp.Roles.Owner, changes: [extends: nil], line: 6}
      ]

      changed = fold(model, change_ops)

      assert changed.roles == %{
               MyApp.Roles.Admin => %{extends: []},
               MyApp.Roles.Owner => %{extends: [MyApp.Roles.Admin]}
             }

      assert fold(changed, removal_ops) == model
    end

    test "changes a role's options as deltas" do
      model = task_model(%{roles: [{:owner, [extends: :editor]}]})

      ops = [
        %{op: :change_role, entity: MyApp.Task, name: :owner, changes: [creator: true], line: 3}
      ]

      assert fold(model, ops) ==
               task_model(%{roles: [{:owner, [creator: true, extends: :editor]}]})
    end

    test "deletes an enum value" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]})

      ops = [
        %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :doing, line: 3}
      ]

      assert fold(model, ops) ==
               task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})
    end

    test "renames an enum value in place and rewrites the default" do
      model =
        task_model(%{
          attributes: [{:status, :enum, [default: :done, values: [:todo, :done, :archived]]}]
        })

      ops = [
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          from: :done,
          to: :completed,
          line: 3
        }
      ]

      assert fold(model, ops) ==
               task_model(%{
                 attributes: [
                   {:status, :enum, [default: :completed, values: [:todo, :completed, :archived]]}
                 ]
               })
    end

    test "reorders enum values" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]})

      ops = [
        %{
          op: :reorder_enum_values,
          entity: MyApp.Task,
          attribute: :status,
          values: [:done, :todo, :doing],
          line: 3
        }
      ]

      assert fold(model, ops) ==
               task_model(%{attributes: [{:status, :enum, [values: [:done, :todo, :doing]]}]})
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

    test "retargets the roles that extend a renamed entity role" do
      model =
        task_model(%{
          roles: [
            {:admin, [extends: [:editor, :owner]]},
            {:editor, []},
            {:owner, [creator: true]}
          ]
        })

      ops = [%{op: :rename_role, entity: MyApp.Task, from: :editor, to: :reviewer, line: 3}]

      assert fold(model, ops) ==
               task_model(%{
                 roles: [
                   {:admin, [extends: [:reviewer, :owner]]},
                   {:owner, [creator: true]},
                   {:reviewer, []}
                 ]
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
               roles: %{},
               user_entity: nil
             }
    end

    test "creates an entity type with no declarations" do
      ops = [%{op: :create_entity, entity: MyApp.Task, line: 3}]

      assert fold(empty(), ops) == %{
               entities: %{MyApp.Task => %{attributes: [], relationships: [], roles: []}},
               roles: %{},
               user_entity: nil
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
               roles: %{},
               user_entity: nil
             }
    end

    test "points the designation at the new name when the designated entity type is renamed" do
      model =
        empty()
        |> fold([%{op: :create_entity, entity: MyApp.User, line: 3}])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :rename_entity, from: MyApp.User, to: MyApp.Account, line: 4}]

      assert fold(model, ops).user_entity == MyApp.Account
    end

    test "leaves the designation alone when another entity type is renamed" do
      model =
        empty()
        |> fold([
          %{op: :create_entity, entity: MyApp.Draft, line: 3},
          %{op: :create_entity, entity: MyApp.User, line: 4}
        ])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 5}]

      assert fold(model, ops).user_entity == MyApp.User
    end

    test "clears the designation when the designated entity type is deleted" do
      model =
        empty()
        |> fold([%{op: :create_entity, entity: MyApp.User, line: 3}])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :delete_entity, entity: MyApp.User, line: 4}]

      assert fold(model, ops).user_entity == nil
    end

    test "leaves the designation alone when another entity type is deleted" do
      model =
        empty()
        |> fold([
          %{op: :create_entity, entity: MyApp.Draft, line: 3},
          %{op: :create_entity, entity: MyApp.User, line: 4}
        ])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :delete_entity, entity: MyApp.Draft, line: 5}]

      assert fold(model, ops).user_entity == MyApp.User
    end

    test "designates an entity type as the user entity type" do
      model = fold(empty(), [%{op: :create_entity, entity: MyApp.User, line: 3}])
      ops = [%{op: :designate_user_entity, entity: MyApp.User, line: 4}]

      assert fold(model, ops).user_entity == MyApp.User
    end

    test "designates an entity type once the previous designation was removed" do
      model =
        empty()
        |> fold([
          %{op: :create_entity, entity: MyApp.Account, line: 3},
          %{op: :create_entity, entity: MyApp.User, line: 4}
        ])
        |> Map.put(:user_entity, MyApp.User)

      ops = [
        %{op: :designate_user_entity, entity: nil, line: 5},
        %{op: :designate_user_entity, entity: MyApp.Account, line: 6}
      ]

      assert fold(model, ops).user_entity == MyApp.Account
    end

    test "keeps the model unchanged when designating the entity type already designated" do
      model =
        empty()
        |> fold([%{op: :create_entity, entity: MyApp.User, line: 3}])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :designate_user_entity, entity: MyApp.User, line: 4}]

      assert fold(model, ops) == model
    end

    test "removes the designation with nil" do
      model =
        empty()
        |> fold([%{op: :create_entity, entity: MyApp.User, line: 3}])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :designate_user_entity, entity: nil, line: 4}]

      assert fold(model, ops).user_entity == nil
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
        roles: %{},
        user_entity: nil
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
               roles: %{},
               user_entity: nil
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

    test "raises when a required attribute is added to an entity type the history carries" do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [],
          line: 3
        }
      ]

      expected_msg =
        "required attributes added without a value for existing rows - " <>
          ":title on MyApp.Task - add backfill: for a one-time value, default: to give " <>
          "every row one, or optional: to leave them empty"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(task_model(%{}), ops) end
    end

    test "allows a required attribute on an entity type created by the same ops" do
      ops = [
        %{op: :create_entity, entity: MyApp.Comment, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Comment,
          name: :body,
          type: :string,
          opts: [],
          line: 4
        }
      ]

      # The table is born here, so there are no rows to leave without a value.
      assert %{entities: entities} = fold(task_model(%{}), ops)
      assert entities[MyApp.Comment].attributes == [{:body, :string, []}]
    end

    test "allows a required attribute carrying a backfill" do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :title,
          type: :string,
          opts: [backfill: "untitled"],
          line: 3
        }
      ]

      # The backfill is a transition value, so it never reaches the model it unblocks.
      assert %{entities: entities} = fold(task_model(%{}), ops)
      assert entities[MyApp.Task].attributes == [{:title, :string, []}]
    end

    test "raises when a backfill carries no value" do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :status,
          type: :string,
          opts: [backfill: nil],
          line: 3
        }
      ]

      expected_msg =
        "backfill: nil on attribute :status of MyApp.Task - a backfill is the value " <>
          "existing rows receive, so it needs one - make the attribute optional: " <>
          "instead, or give the backfill a value"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(task_model(%{}), ops) end
    end

    test "raises when a deleted entity type is still targeted by a relationship" do
      model =
        fold(empty(), [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [],
            line: 5
          }
        ])

      ops = [%{op: :delete_entity, entity: MyApp.User, line: 3}]

      expected_msg =
        "relationship targets deleted at this point in migration history - " <>
          ":author on MyApp.Task targets MyApp.User - delete the relationship in the " <>
          "migration that deletes its target, or an earlier one"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "allows a migration deleting an entity type before the relationship targeting it" do
      model =
        fold(empty(), [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [],
            line: 5
          }
        ])

      # The order the generator emits - what a file leaves behind is what counts, not the
      # order its ops take to get there.
      ops = [
        %{op: :delete_entity, entity: MyApp.User, line: 3},
        %{op: :delete_relationship, entity: MyApp.Task, name: :author, line: 4}
      ]

      assert %{entities: entities} = fold(model, ops)
      assert Map.keys(entities) == [MyApp.Task]
      assert entities[MyApp.Task].relationships == []
    end

    test "allows a migration deleting and recreating an entity type a relationship targets" do
      model =
        fold(empty(), [
          %{op: :create_entity, entity: MyApp.User, line: 3},
          %{op: :create_entity, entity: MyApp.Task, line: 4},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :author,
            type: MyApp.User,
            opts: [],
            line: 5
          }
        ])

      ops = [
        %{op: :delete_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.User, line: 4}
      ]

      assert %{entities: entities} = fold(model, ops)

      entity_types =
        entities
        |> Map.keys()
        |> Enum.sort()

      assert entity_types == [MyApp.Task, MyApp.User]
      assert entities[MyApp.Task].relationships == [{:author, MyApp.User, []}]
    end

    test "raises when adding an :enum attribute without values" do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :status,
          type: :enum,
          opts: [],
          line: 3
        }
      ]

      expected_msg = "adding attribute :status to MyApp.Task as :enum requires values:"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(task_model(%{}), ops) end
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

    test "raises when deleting an entity role that other roles extend" do
      model =
        task_model(%{
          roles: [{:admin, [extends: [:viewer]]}, {:owner, [extends: :viewer]}, {:viewer, []}]
        })

      ops = [%{op: :delete_role, entity: MyApp.Task, name: :viewer, line: 3}]

      expected_msg =
        "role :viewer on MyApp.Task is extended by :admin, :owner - " <>
          "delete or change the extending roles first"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
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

    test "raises when an enum op targets a non-enum attribute" do
      model = task_model(%{attributes: [{:status, :string, []}]})

      ops = [
        %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :done, line: 3}
      ]

      expected_msg = "attribute :status on MyApp.Task is not an :enum attribute"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when adding an enum value that already exists" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :done,
          opts: [],
          line: 3
        }
      ]

      expected_msg =
        "enum value :done already exists on attribute :status " <>
          "of MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when adding an enum value with both position options" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :doing,
          opts: [before: :done, after: :todo],
          line: 3
        }
      ]

      expected_msg = "add_enum_value takes at most one of before: and after:"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when renaming an enum value that does not exist" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          from: :doing,
          to: :in_progress,
          line: 3
        }
      ]

      expected_msg =
        "no such enum value :doing on attribute :status " <>
          "of MyApp.Task at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when deleting an enum value that is the default" do
      model =
        task_model(%{attributes: [{:status, :enum, [default: :done, values: [:todo, :done]]}]})

      ops = [
        %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :done, line: 3}
      ]

      expected_msg =
        "enum value :done is the default of attribute :status on MyApp.Task - " <>
          "change the default before deleting the value"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when a reorder is not a permutation of the current values" do
      model = task_model(%{attributes: [{:status, :enum, [values: [:todo, :done]]}]})

      ops = [
        %{
          op: :reorder_enum_values,
          entity: MyApp.Task,
          attribute: :status,
          values: [:todo, :completed],
          line: 3
        }
      ]

      expected_msg =
        "reorder_enum_values changes order only - :done is missing and :completed is new - " <>
          "a rename is rename_enum_value, a removal is delete_enum_value, " <>
          "an addition is add_enum_value"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when adding a global role that already exists" do
      model = fold(empty(), [%{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 3}])
      ops = [%{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 4}]

      expected_msg = "role MyApp.Roles.Admin already exists at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when deleting a global role that does not exist" do
      ops = [%{op: :delete_role, role: MyApp.Roles.Admin, line: 3}]

      expected_msg = "no such role MyApp.Roles.Admin at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(empty(), ops) end
    end

    test "raises when deleting a global role that other roles extend" do
      model =
        fold(empty(), [
          %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 3},
          %{op: :add_role, role: MyApp.Roles.Owner, opts: [extends: MyApp.Roles.Admin], line: 4}
        ])

      ops = [%{op: :delete_role, role: MyApp.Roles.Admin, line: 5}]

      expected_msg =
        "role MyApp.Roles.Admin is extended by MyApp.Roles.Owner - " <>
          "delete or change the extending roles first"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end

    test "raises when designating an entity type that does not exist" do
      ops = [%{op: :designate_user_entity, entity: MyApp.Ghost, line: 3}]

      expected_msg = "no such entity MyApp.Ghost at this point in migration history"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(empty(), ops) end
    end

    test "raises when moving the designation between entity types directly" do
      model =
        empty()
        |> fold([
          %{op: :create_entity, entity: MyApp.Account, line: 3},
          %{op: :create_entity, entity: MyApp.User, line: 4}
        ])
        |> Map.put(:user_entity, MyApp.User)

      ops = [%{op: :designate_user_entity, entity: MyApp.Account, line: 5}]

      expected_msg =
        "the user entity designation cannot move directly from MyApp.User to " <>
          "MyApp.Account - role grants reference MyApp.User rows, so they cannot follow " <>
          "it - remove `user: true` from MyApp.User and run `mix holo.gen.migration` " <>
          "(that migration drops the role grant store), then add `user: true` to " <>
          "MyApp.Account and run it again"

      assert_error Hologram.CompileError, expected_msg, fn -> fold(model, ops) end
    end
  end

  describe "from_modules/2" do
    test "records the designated user entity type" do
      assert from_modules([Module1, Module14]).user_entity == Module14
    end

    test "records no designation when none of the given entity types carries it" do
      assert from_modules([Module1, Module2]).user_entity == nil
    end

    test "derives an entry for an entity type without declarations" do
      assert from_modules([Module1]) == %{
               entities: %{Module1 => %{attributes: [], relationships: [], roles: []}},
               roles: %{},
               user_entity: nil
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
               roles: %{},
               user_entity: nil
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
               roles: %{},
               user_entity: nil
             }
    end

    test "derives global role entries from the given role modules" do
      assert from_modules([], [RoleModule1, RoleModule2]) == %{
               entities: %{},
               roles: %{
                 RoleModule1 => %{extends: RoleModule1.__extends__()},
                 RoleModule2 => %{extends: RoleModule2.__extends__()}
               },
               user_entity: nil
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
               roles: %{},
               user_entity: nil
             }
    end

    test "returns equal terms regardless of the given module order" do
      assert from_modules([Module13, Module2]) == from_modules([Module2, Module13])
    end
  end

  describe "neutral_value/1" do
    test "returns false for a flag option" do
      assert neutral_value(:optional) == false
    end

    test "returns nil for a value option" do
      assert neutral_value(:default) == nil
    end
  end
end
