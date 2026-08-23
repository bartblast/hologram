defmodule Hologram.Migration.RendererTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Renderer

  alias Hologram.Entity.Model
  alias Hologram.Test.Fixtures.Entity.Module14, as: UserEntity

  # A term holding the user entity type designates it - the grant store derives from the
  # designation, so the tests that include it are the ones exercising the store.
  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry = Map.merge(%{attributes: [], relationships: [], roles: []}, entry_overrides)

        {entity_type, entry}
      end)

    user_entity = if Map.has_key?(entries, UserEntity), do: UserEntity

    %{entities: entries, roles: %{}, user_entity: user_entity}
  end

  defp op_kinds(ops), do: Enum.map(ops, & &1.op)

  describe "render/2" do
    test "renders an entity creation as its table with columns and constraints" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: [], line: 4}
      ]

      result = render(ops, Model.empty())

      assert result.tail == []

      created_tables =
        result.transactional
        |> Enum.filter(&(&1.op == :create_table))
        |> Enum.map(& &1.table)

      assert created_tables == ["my_app_task"]

      task_table =
        Enum.find(result.transactional, &(&1.op == :create_table and &1.table == "my_app_task"))

      assert Map.keys(task_table.columns) == [
               "created_at",
               "id",
               "title",
               "title_$sort",
               "updated_at"
             ]

      assert task_table.primary_key.constraint == "my_app_task_$pk"

      assert result.post_model ==
               model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})
    end

    test "renders an added attribute as its column, carrying the backfill" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [backfill: 0],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [add_column] = result.transactional
      assert add_column.op == :add_column
      assert add_column.table == "my_app_task"
      assert add_column.column == "priority"
      assert add_column.backfill == 0
      assert add_column.definition.null == false
    end

    test "leaves the backfill out of the model it produces" do
      pre = model(%{MyApp.Task => %{attributes: []}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [backfill: 0],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert result.post_model ==
               model(%{MyApp.Task => %{attributes: [{:priority, :integer, []}]}})
    end

    test "renders a deleted attribute as its column drop, the sort-key companion following" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:legacy, :string, []}, {:title, :string, []}]}
        })

      ops = [%{op: :delete_attribute, entity: MyApp.Task, name: :legacy, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :drop_index, index: "my_app_task_legacy_$sort_$idx"},
               %{op: :drop_column, table: "my_app_task", column: "legacy"},
               %{op: :drop_column, table: "my_app_task", column: "legacy_$sort"}
             ]
    end

    test "renders a deleted entity as its table drop" do
      pre = model(%{MyApp.Archive => %{}, MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :delete_entity, entity: MyApp.Archive, line: 3}]

      result = render(ops, pre)

      # The grant store follows the model: its resource_type value goes with the table,
      # and PostgreSQL removes an enum value only by rebuilding the type.
      assert op_kinds(result.transactional) == [:drop_table, :rebuild_enum_type]

      assert Enum.find(result.transactional, &(&1.op == :drop_table)).table == "my_app_archive"
      assert result.post_model == model(%{MyApp.Task => %{}, UserEntity => %{}})
    end

    test "renders a to-one relationship as its reference column, constraint, and index" do
      pre = model(%{MyApp.Task => %{}, MyApp.User => %{}})

      ops = [
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [optional: true],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert op_kinds(result.transactional) == [:add_column, :add_foreign_key]
      assert [create_index] = result.tail

      assert create_index.index == "my_app_task_author_id_$idx"
      assert create_index.concurrently == true
    end

    test "renders a to-many relationship as its join table" do
      pre = model(%{MyApp.Tag => %{}, MyApp.Task => %{}})

      ops = [
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :tags,
          type: [MyApp.Tag],
          opts: [],
          line: 3
        }
      ]

      result = render(ops, pre)

      # The join table is born here, so its reverse index builds inside the transaction.
      assert result.tail == []

      assert op_kinds(result.transactional) == [
               :create_table,
               :add_foreign_key,
               :add_foreign_key,
               :create_index
             ]

      assert Enum.find(result.transactional, &(&1.op == :create_index)).table ==
               "my_app_task_tags_$join"
    end

    test "builds indexes of tables born in the file inside the transaction" do
      ops = [
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
      ]

      result = render(ops, Model.empty())

      assert result.tail == []
      assert :create_index in op_kinds(result.transactional)
    end

    test "builds a unique index of a table born in the file inside the transaction" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :slug,
          type: :string,
          opts: [unique: true],
          line: 4
        }
      ]

      result = render(ops, Model.empty())

      assert result.tail == []

      assert %{index: "my_app_task_slug_$uidx", unique: true} =
               Enum.find(result.transactional, &(&1.op == :create_index and &1.unique))
    end

    test "builds a unique index of a table that predates the file in the tail" do
      pre = model(%{MyApp.Task => %{attributes: [{:slug, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :slug,
          changes: [unique: true],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert result.transactional == []
      assert [create_index] = result.tail

      assert create_index.index == "my_app_task_slug_$uidx"
      assert create_index.unique == true
      assert create_index.concurrently == true
    end

    test "defers the referencing ops past the objects they name" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [],
          line: 4
        },
        %{op: :create_entity, entity: MyApp.User, line: 5}
      ]

      result = render(ops, Model.empty())
      kinds = op_kinds(result.transactional)

      reversed_kinds = Enum.reverse(kinds)
      last_create = Enum.find_index(reversed_kinds, &(&1 == :create_table))
      first_reference = Enum.find_index(reversed_kinds, &(&1 == :add_foreign_key))

      assert Enum.count(kinds, &(&1 == :create_table)) == 2
      assert first_reference < last_create
    end

    test "renders an entity rename as its table and every name derived from it" do
      pre =
        model(%{
          MyApp.Draft => %{
            attributes: [{:status, :enum, [values: [:todo, :done]]}],
            relationships: [{:author, MyApp.User, []}, {:tags, [MyApp.Tag], []}]
          },
          MyApp.Tag => %{},
          MyApp.User => %{},
          UserEntity => %{}
        })

      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3}]

      result = render(ops, pre)

      assert result.tail == []

      assert result.transactional == [
               %{op: :rename_table, from: "my_app_draft", to: "my_app_sketch"},
               %{
                 op: :rename_constraint,
                 table: "my_app_sketch",
                 from: "my_app_draft_$pk",
                 to: "my_app_sketch_$pk"
               },
               %{
                 op: :rename_enum_type,
                 from: "my_app_draft_status_$enum",
                 to: "my_app_sketch_status_$enum"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_sketch",
                 from: "my_app_draft_author_id_$fk",
                 to: "my_app_sketch_author_id_$fk"
               },
               %{
                 op: :rename_index,
                 from: "my_app_draft_author_id_$idx",
                 to: "my_app_sketch_author_id_$idx"
               },
               %{
                 op: :rename_table,
                 from: "my_app_draft_tags_$join",
                 to: "my_app_sketch_tags_$join"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_sketch_tags_$join",
                 from: "my_app_draft_tags_$join_$pk",
                 to: "my_app_sketch_tags_$join_$pk"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_sketch_tags_$join",
                 from: "my_app_draft_tags_$join_source_id_$fk",
                 to: "my_app_sketch_tags_$join_source_id_$fk"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_sketch_tags_$join",
                 from: "my_app_draft_tags_$join_target_id_$fk",
                 to: "my_app_sketch_tags_$join_target_id_$fk"
               },
               %{
                 op: :rename_index,
                 from: "my_app_draft_tags_$join_target_id_$idx",
                 to: "my_app_sketch_tags_$join_target_id_$idx"
               },
               %{
                 op: :rename_enum_value,
                 enum_type: "hologram_role_grant_resource_type_$enum",
                 from: "my_app_draft",
                 to: "my_app_sketch"
               }
             ]
    end

    test "renames the sort-key companion with its string attribute" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "title", to: "name"},
               %{op: :rename_column, table: "my_app_task", from: "title_$sort", to: "name_$sort"},
               %{
                 op: :rename_index,
                 from: "my_app_task_title_$sort_$idx",
                 to: "my_app_task_name_$sort_$idx"
               }
             ]
    end

    test "renders an attribute rename as its column, enum type following" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:state, :enum, [values: [:todo, :done]]}]}
        })

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :state, to: :status, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "state", to: "status"},
               %{
                 op: :rename_enum_type,
                 from: "my_app_task_state_$enum",
                 to: "my_app_task_status_$enum"
               }
             ]
    end

    test "renders a to-one relationship rename as its reference column and derived names" do
      pre =
        model(%{MyApp.Task => %{relationships: [{:author, MyApp.User, []}]}, MyApp.User => %{}})

      ops = [
        %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator, line: 3}
      ]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "author_id", to: "creator_id"},
               %{
                 op: :rename_constraint,
                 table: "my_app_task",
                 from: "my_app_task_author_id_$fk",
                 to: "my_app_task_creator_id_$fk"
               },
               %{
                 op: :rename_index,
                 from: "my_app_task_author_id_$idx",
                 to: "my_app_task_creator_id_$idx"
               }
             ]
    end

    test "renders a to-many relationship rename as its join table and derived names" do
      pre = model(%{MyApp.Tag => %{}, MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], []}]}})

      ops = [%{op: :rename_relationship, entity: MyApp.Task, from: :tags, to: :labels, line: 3}]

      result = render(ops, pre)

      assert op_kinds(result.transactional) == [
               :rename_table,
               :rename_constraint,
               :rename_constraint,
               :rename_constraint,
               :rename_index
             ]

      assert hd(result.transactional) == %{
               op: :rename_table,
               from: "my_app_task_tags_$join",
               to: "my_app_task_labels_$join"
             }
    end

    # Both of the store's enums derive SORTED, and a value rename moves a label without moving
    # its position - so a new label that sorts elsewhere leaves the database in an order the
    # model does not derive, which the drift check refuses on the next boot.
    test "renders an entity rename that moves its resource_type position as a rebuild" do
      pre = model(%{MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :rename_entity, from: UserEntity, to: MyApp.Account, line: 3}]

      result = render(ops, pre)

      assert Enum.find(result.transactional, &(&1.op == :rebuild_enum_type)) == %{
               op: :rebuild_enum_type,
               enum_type: "hologram_role_grant_resource_type_$enum",
               values: ["my_app_account", "my_app_task"],
               columns: [{"hologram_role_grant", "resource_type"}],
               remap: [
                 %{from: "test_fixtures_entity_module14", to: "my_app_account", scope: nil}
               ]
             }

      refute Enum.any?(result.transactional, &(&1.op == :rename_enum_value))
    end

    test "renders an entity rename that keeps its resource_type position as a value rename" do
      pre = model(%{MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :rename_entity, from: UserEntity, to: MyApp.Zebra, line: 3}]

      result = render(ops, pre)

      assert Enum.find(result.transactional, &(&1.op == :rename_enum_value)) == %{
               op: :rename_enum_value,
               enum_type: "hologram_role_grant_resource_type_$enum",
               from: "test_fixtures_entity_module14",
               to: "my_app_zebra"
             }

      refute Enum.any?(result.transactional, &(&1.op == :rebuild_enum_type))
    end

    test "renders a role rename that moves its position as a rebuild" do
      pre =
        model(%{
          MyApp.Task => %{roles: [{:editor, []}, {:viewer, []}]},
          UserEntity => %{}
        })

      ops = [%{op: :rename_role, entity: MyApp.Task, from: :viewer, to: :admin, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{
                 op: :rebuild_enum_type,
                 enum_type: "hologram_role_grant_role_$enum",
                 values: ["admin", "editor"],
                 columns: [{"hologram_role_grant", "role"}],
                 remap: [%{from: "viewer", to: "admin", scope: nil}]
               }
             ]
    end

    test "renders a role rename no other entity type shares as a value rename" do
      pre = model(%{MyApp.Task => %{roles: [{:moderator, []}]}, UserEntity => %{}})

      ops = [
        %{op: :rename_role, entity: MyApp.Task, from: :moderator, to: :maintainer, line: 3}
      ]

      result = render(ops, pre)

      assert result.transactional == [
               %{
                 op: :rename_enum_value,
                 enum_type: "hologram_role_grant_role_$enum",
                 from: "moderator",
                 to: "maintainer"
               }
             ]
    end

    test "renders a role rename another entity type shares as a scoped rebuild" do
      pre =
        model(%{
          MyApp.Other => %{roles: [{:editor, []}]},
          MyApp.Task => %{roles: [{:editor, []}]},
          UserEntity => %{}
        })

      ops = [%{op: :rename_role, entity: MyApp.Task, from: :editor, to: :reviewer, line: 3}]

      result = render(ops, pre)

      # A value rename would relabel MyApp.Other's grants too, and drop a value the model
      # still requires. The rebuild keeps "editor" for MyApp.Other and moves only the rows
      # whose resource_type is MyApp.Task's table.
      assert result.transactional == [
               %{
                 op: :rebuild_enum_type,
                 enum_type: "hologram_role_grant_role_$enum",
                 values: ["editor", "reviewer"],
                 columns: [{"hologram_role_grant", "role"}],
                 remap: [
                   %{
                     from: "editor",
                     to: "reviewer",
                     scope: {"resource_type", "my_app_task"}
                   }
                 ]
               }
             ]
    end

    test "renders a global role rename as the grant store's value rename" do
      pre = %{
        entities: %{
          MyApp.Task => %{attributes: [], relationships: [], roles: []},
          UserEntity => %{attributes: [], relationships: [], roles: []}
        },
        roles: %{MyApp.Roles.Moderator => %{extends: []}},
        user_entity: UserEntity
      }

      ops = [
        %{op: :rename_role, from: MyApp.Roles.Moderator, to: MyApp.Roles.Maintainer, line: 3}
      ]

      result = render(ops, pre)

      assert result.transactional == [
               %{
                 op: :rename_enum_value,
                 enum_type: "hologram_role_grant_role_$enum",
                 from: "MyApp.Roles.Moderator",
                 to: "MyApp.Roles.Maintainer"
               }
             ]
    end

    test "renders an enum value rename as the attribute type's value rename" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

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

      result = render(ops, pre)

      assert result.transactional == [
               %{
                 op: :rename_enum_value,
                 enum_type: "my_app_task_status_$enum",
                 from: "done",
                 to: "completed"
               }
             ]
    end

    test "renders renames and other changes in file order" do
      pre = model(%{MyApp.Draft => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Sketch,
          name: :summary,
          type: :string,
          opts: [optional: true],
          line: 4
        }
      ]

      result = render(ops, pre)
      kinds = op_kinds(result.transactional)

      assert Enum.at(kinds, 0) == :rename_table
      assert List.last(kinds) == :add_column

      add_columns = Enum.filter(result.transactional, &(&1.op == :add_column))

      assert Enum.map(add_columns, &{&1.table, &1.column}) == [
               {"my_app_sketch", "summary"},
               {"my_app_sketch", "summary_$sort"}
             ]
    end

    test "renders an attribute type change as its column alteration" do
      pre = model(%{MyApp.Task => %{attributes: [{:estimate, :integer, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :estimate,
          changes: [type: :float],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [alter_column] = result.transactional
      assert alter_column.op == :alter_column
      assert alter_column.table == "my_app_task"
      assert alter_column.column == "estimate"
      assert alter_column.before.type == "int8"
      assert alter_column.after.type == "float8"
    end

    test "renders an optional flip as its column nullability" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [optional: true],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [alter_column] = result.transactional
      assert alter_column.op == :alter_column
      assert alter_column.before.null == false
      assert alter_column.after.null == true
    end

    test "renders nothing for changes the physical schema does not carry" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:priority, :integer, [optional: true]}],
            roles: [{:owner, []}]
          }
        })

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :priority,
          changes: [default: 0],
          line: 3
        },
        %{op: :change_role, entity: MyApp.Task, name: :owner, changes: [creator: true], line: 4}
      ]

      result = render(ops, pre)

      assert result.transactional == []
      assert result.tail == []

      assert result.post_model ==
               model(%{
                 MyApp.Task => %{
                   attributes: [{:priority, :integer, [default: 0, optional: true]}],
                   roles: [{:owner, [creator: true]}]
                 }
               })
    end

    test "renders a deleted enum value as its type rebuild" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]}
        })

      ops = [
        %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :doing, line: 3}
      ]

      result = render(ops, pre)

      assert [rebuild] = result.transactional
      assert rebuild.op == :rebuild_enum_type
      assert rebuild.enum_type == "my_app_task_status_$enum"
      assert rebuild.values == ["todo", "done"]
      assert rebuild.columns == [{"my_app_task", "status"}]
    end

    test "renders reordered enum values as their type rebuild" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]}
        })

      ops = [
        %{
          op: :reorder_enum_values,
          entity: MyApp.Task,
          attribute: :status,
          values: [:done, :todo, :doing],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [rebuild] = result.transactional
      assert rebuild.op == :rebuild_enum_type
      assert rebuild.values == ["done", "todo", "doing"]
    end

    test "renders a global role addition as the grant store's value" do
      pre = %{
        entities: %{
          MyApp.Task => %{attributes: [], relationships: [], roles: []},
          UserEntity => %{attributes: [], relationships: [], roles: []}
        },
        roles: %{},
        user_entity: UserEntity
      }

      ops = [%{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 3}]

      result = render(ops, pre)

      assert [add_enum_value] = result.transactional
      assert add_enum_value.op == :add_enum_value
      assert add_enum_value.enum_type == "hologram_role_grant_role_$enum"
      assert add_enum_value.value == "MyApp.Roles.Admin"
    end

    # The designation op carries no physical form of its own - the grant store is derived,
    # so its DDL falls out of the diff between the models the op folds between. These pin
    # what that produces, which is why they needed no renderer change to pass.
    test "renders the first user entity designation as the grant store's creation" do
      undesignated = model(%{UserEntity => %{}})
      pre = Map.put(undesignated, :user_entity, nil)
      ops = [%{op: :designate_user_entity, entity: UserEntity, line: 3}]

      result = render(ops, pre)

      assert op_kinds(result.transactional) == [
               :create_enum_type,
               :create_enum_type,
               :create_table,
               :add_foreign_key,
               :add_foreign_key,
               :create_index,
               :create_index,
               :create_index
             ]

      assert Enum.find(result.transactional, &(&1.op == :create_table)).table ==
               "hologram_role_grant"

      assert result.tail == []
    end

    test "empties the grant store before re-pointing its references" do
      pre = model(%{MyApp.Member => %{}, UserEntity => %{}})

      ops = [
        %{op: :delete_role_grants, line: 3},
        %{op: :designate_user_entity, entity: MyApp.Member, line: 4}
      ]

      result = render(ops, pre)

      # The delete comes FIRST: the added keys validate against whatever rows remain, so
      # emptying the store after them would be emptying it too late.
      assert op_kinds(result.transactional) == [
               :delete_role_grants,
               :drop_foreign_key,
               :drop_foreign_key,
               :add_foreign_key,
               :add_foreign_key
             ]

      assert hd(result.transactional).table == "hologram_role_grant"
      assert result.tail == []
    end

    test "empties the grant store before dropping it" do
      pre = model(%{UserEntity => %{}})

      ops = [
        %{op: :delete_role_grants, line: 3},
        %{op: :designate_user_entity, entity: nil, line: 4}
      ]

      result = render(ops, pre)

      # The store's two references to the user entity type drop ahead of the table itself,
      # so the user entity table is droppable whatever the two names sort like.
      assert op_kinds(result.transactional) == [
               :delete_role_grants,
               :drop_foreign_key,
               :drop_foreign_key,
               :drop_table,
               :drop_enum_type,
               :drop_enum_type
             ]

      assert result.tail == []
    end

    test "renders a widened relationship as its join table, the values moving into it" do
      pre = model(%{MyApp.Tag => %{}, MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}})

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :tags,
          changes: [type: [MyApp.Tag]],
          line: 3
        }
      ]

      result = render(ops, pre)
      kinds = op_kinds(result.transactional)

      # The join table exists before the values move, and the column they came from
      # survives until they have.
      assert Enum.find_index(kinds, &(&1 == :create_table)) <
               Enum.find_index(kinds, &(&1 == :widen_to_many))

      assert Enum.find_index(kinds, &(&1 == :widen_to_many)) <
               Enum.find_index(kinds, &(&1 == :drop_column))

      assert Enum.find(result.transactional, &(&1.op == :widen_to_many)) == %{
               op: :widen_to_many,
               table: "my_app_task",
               join_table: "my_app_task_tags_$join",
               column: "tags_id"
             }
    end

    test "refuses to narrow a relationship whose rows may hold several targets" do
      pre = model(%{MyApp.Tag => %{}, MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], []}]}})

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :tags,
          changes: [type: MyApp.Tag],
          line: 3
        }
      ]

      expected_msg =
        "changing relationship :tags on MyApp.Task from to-many to to-one is not supported - " <>
          "a row holding several targets has no one target to keep - " <>
          "delete the relationship and add it with the new cardinality, " <>
          "or write the migration that picks the survivors"

      assert_error Hologram.CompileError, expected_msg, fn -> render(ops, pre) end
    end

    test "renders a relationship pointed at another entity type as its reference change" do
      pre =
        model(%{
          MyApp.Account => %{},
          MyApp.Task => %{relationships: [{:author, MyApp.User, []}]},
          MyApp.User => %{}
        })

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :author,
          changes: [type: MyApp.Account],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert op_kinds(result.transactional) == [:drop_foreign_key, :add_foreign_key]

      assert Enum.find(result.transactional, &(&1.op == :add_foreign_key)).references ==
               "my_app_account"
    end

    test "renders an added enum value as its type value" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      ops = [
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :archived,
          opts: [],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [add_enum_value] = result.transactional
      assert add_enum_value.op == :add_enum_value
      assert add_enum_value.enum_type == "my_app_task_status_$enum"
      assert add_enum_value.value == "archived"
    end

    test "returns an empty render for ops with no physical shadow" do
      pre = model(%{MyApp.Task => %{roles: [{:editor, []}]}})

      ops = [
        %{
          op: :change_role,
          entity: MyApp.Task,
          name: :editor,
          changes: [creator: true],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert result.transactional == []
      assert result.tail == []
      assert result.post_model == model(%{MyApp.Task => %{roles: [{:editor, [creator: true]}]}})
    end
  end
end
