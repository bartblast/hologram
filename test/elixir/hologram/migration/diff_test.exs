defmodule Hologram.Migration.DiffTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Diff

  alias Hologram.Entity.Model

  defp model(entities, roles \\ %{}) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry =
          Map.merge(
            %{attributes: [], relationships: [], roles: []},
            entry_overrides
          )

        {entity_type, entry}
      end)

    %{entities: entries, roles: roles, user_entity: nil}
  end

  describe "diff/2" do
    test "returns an empty plan for equal models" do
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert diff(current, current) == %{ops: [], questions: []}
    end

    test "emits creation ops for a created entity type" do
      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:priority, :integer, [optional: true]}, {:title, :string, []}],
            relationships: [{:author, MyApp.User, []}],
            roles: [{:editor, []}]
          }
        })

      assert diff(Model.empty(), current) == %{
               ops: [
                 %{op: :create_entity, entity: MyApp.Task},
                 %{
                   op: :add_attribute,
                   entity: MyApp.Task,
                   name: :priority,
                   type: :integer,
                   opts: [optional: true]
                 },
                 %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: []},
                 %{
                   op: :add_relationship,
                   entity: MyApp.Task,
                   name: :author,
                   type: MyApp.User,
                   opts: []
                 },
                 %{op: :add_role, entity: MyApp.Task, name: :editor, opts: []}
               ],
               questions: []
             }
    end

    test "emits a deletion op for a deleted entity type" do
      replayed = model(%{MyApp.Archive => %{}})

      assert diff(replayed, Model.empty()) == %{
               ops: [%{op: :delete_entity, entity: MyApp.Archive}],
               questions: []
             }
    end

    test "emits the designation when an existing entity type becomes the user entity type" do
      replayed = model(%{MyApp.Account => %{}})
      current = Map.put(replayed, :user_entity, MyApp.Account)

      assert diff(replayed, current) == %{
               ops: [%{op: :designate_user_entity, entity: MyApp.Account}],
               questions: []
             }
    end

    test "emits the designation after the ops creating the entity type it names" do
      current =
        %{MyApp.Account => %{attributes: [{:email, :string, []}]}}
        |> model()
        |> Map.put(:user_entity, MyApp.Account)

      ops = diff(Model.empty(), current).ops

      assert List.last(ops) == %{op: :designate_user_entity, entity: MyApp.Account}
    end

    test "withholds a removed designation into a question" do
      current = model(%{MyApp.Account => %{}})
      replayed = Map.put(current, :user_entity, MyApp.Account)

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :user_entity,
                   from: MyApp.Account,
                   to: nil,
                   withheld_ops: [
                     %{op: :delete_role_grants},
                     %{op: :designate_user_entity, entity: nil}
                   ]
                 }
               ]
             }
    end

    test "withholds a moved designation into a question" do
      built = model(%{MyApp.Account => %{}, MyApp.Member => %{}})
      replayed = Map.put(built, :user_entity, MyApp.Account)
      current = Map.put(built, :user_entity, MyApp.Member)

      # Resolving it means writing the line that empties the grant store - the generator
      # never writes grant destruction on its own.
      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :user_entity,
                   from: MyApp.Account,
                   to: MyApp.Member,
                   withheld_ops: [
                     %{op: :delete_role_grants},
                     %{op: :designate_user_entity, entity: MyApp.Member}
                   ]
                 }
               ]
             }
    end

    test "withholds a designation whose entity type was deleted into a question" do
      replayed =
        %{MyApp.Account => %{}}
        |> model()
        |> Map.put(:user_entity, MyApp.Account)

      assert diff(replayed, Model.empty()) == %{
               ops: [%{op: :delete_entity, entity: MyApp.Account}],
               questions: [
                 %{
                   kind: :user_entity,
                   from: MyApp.Account,
                   to: nil,
                   withheld_ops: [
                     %{op: :delete_role_grants},
                     %{op: :designate_user_entity, entity: nil}
                   ]
                 }
               ]
             }
    end

    test "withholds a designation moving off a deleted entity type into a question" do
      replayed =
        %{MyApp.Account => %{}, MyApp.Member => %{}}
        |> model()
        |> Map.put(:user_entity, MyApp.Account)

      current =
        %{MyApp.Member => %{}}
        |> model()
        |> Map.put(:user_entity, MyApp.Member)

      # The grants describe rows the deletion takes away, so the arriving designation is
      # no more emittable on its own than one moving between surviving types.
      assert diff(replayed, current) == %{
               ops: [%{op: :delete_entity, entity: MyApp.Account}],
               questions: [
                 %{
                   kind: :user_entity,
                   from: MyApp.Account,
                   to: MyApp.Member,
                   withheld_ops: [
                     %{op: :delete_role_grants},
                     %{op: :designate_user_entity, entity: MyApp.Member}
                   ]
                 }
               ]
             }
    end

    test "withholds entity creations and deletions into a question" do
      replayed = model(%{MyApp.Draft => %{attributes: [{:body, :string, []}]}})

      current =
        model(%{
          MyApp.Marker => %{},
          MyApp.Sketch => %{attributes: [{:body, :string, []}]}
        })

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :entities,
                   deleted: [MyApp.Draft],
                   added: [MyApp.Marker, MyApp.Sketch],
                   hints: [{:rename, MyApp.Draft, MyApp.Sketch}],
                   withheld_ops: [
                     %{op: :create_entity, entity: MyApp.Marker},
                     %{op: :create_entity, entity: MyApp.Sketch},
                     %{
                       op: :add_attribute,
                       entity: MyApp.Sketch,
                       name: :body,
                       type: :string,
                       opts: []
                     },
                     %{op: :delete_entity, entity: MyApp.Draft}
                   ]
                 }
               ]
             }
    end

    test "emits member add and delete ops for a surviving entity type" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:title, :string, []}],
            relationships: [{:legacy_project, MyApp.Project, []}]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:priority, :integer, [optional: true]}, {:title, :string, []}],
            roles: [{:editor, []}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :add_attribute,
                   entity: MyApp.Task,
                   name: :priority,
                   type: :integer,
                   opts: [optional: true]
                 },
                 %{op: :delete_relationship, entity: MyApp.Task, name: :legacy_project},
                 %{op: :add_role, entity: MyApp.Task, name: :editor, opts: []}
               ],
               questions: []
             }
    end

    test "withholds a required attribute added to a surviving entity type into a question" do
      replayed = model(%{MyApp.Task => %{}})
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :fill,
                   entity: MyApp.Task,
                   attributes: [:title],
                   members: [{:title, :string, []}],
                   withheld_ops: [
                     %{
                       op: :add_attribute,
                       entity: MyApp.Task,
                       name: :title,
                       type: :string,
                       opts: []
                     }
                   ]
                 }
               ]
             }
    end

    test "emits a required attribute of a created entity type without a question" do
      replayed = model(%{})
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      # The table is born in this migration, so it holds no rows to leave without a value.
      assert %{ops: ops, questions: []} = diff(replayed, current)
      assert Enum.map(ops, & &1.op) == [:create_entity, :add_attribute]
    end

    test "emits an added attribute carrying a fill without a question" do
      replayed = model(%{MyApp.Task => %{}})

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:done, :boolean, [default: false]}, {:note, :string, [optional: true]}]
          }
        })

      assert %{ops: ops, questions: []} = diff(replayed, current)
      assert Enum.map(ops, & &1.name) == [:done, :note]
    end

    test "emits change deltas for surviving members" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:estimate, :integer, [default: 0, min: 0, optional: true]}],
            relationships: [{:tags, [MyApp.Tag], []}],
            roles: [{:owner, [granted_to: :creator]}]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:estimate, :float, [max: 10, min: 0]}],
            relationships: [{:tags, [MyApp.Label], [optional: true]}],
            roles: [{:owner, [extends: :editor]}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :estimate,
                   changes: [default: nil, max: 10, optional: false, type: :float]
                 },
                 %{
                   op: :change_relationship,
                   entity: MyApp.Task,
                   name: :tags,
                   changes: [optional: true, type: [MyApp.Label]]
                 },
                 %{
                   op: :change_role,
                   entity: MyApp.Task,
                   name: :owner,
                   changes: [extends: :editor, granted_to: nil]
                 }
               ],
               questions: []
             }
    end

    test "includes the initial values when an attribute becomes an enum" do
      replayed = model(%{MyApp.Task => %{attributes: [{:status, :string, []}]}})

      current =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :status,
                   changes: [type: :enum, values: [:todo, :done]]
                 }
               ],
               questions: []
             }
    end

    test "excludes the values from the delta of a surviving enum attribute" do
      replayed =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:status, :enum, [optional: true, values: [:todo, :done, :archived]]}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :status,
                   changes: [optional: true]
                 },
                 %{
                   op: :add_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :archived,
                   opts: [after: :done]
                 }
               ],
               questions: []
             }
    end

    test "excludes the values from the delta when an attribute leaves enum" do
      replayed =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      current = model(%{MyApp.Task => %{attributes: [{:status, :string, []}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :status,
                   changes: [type: :string]
                 }
               ],
               questions: []
             }
    end

    test "emits change_attribute when an attribute becomes unique" do
      replayed = model(%{MyApp.Task => %{attributes: [{:slug, :string, []}]}})
      current = model(%{MyApp.Task => %{attributes: [{:slug, :string, [unique: true]}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :slug,
                   changes: [unique: true]
                 }
               ],
               questions: []
             }
    end

    # The delta spells the removal as the option's neutral value rather than as nil, which is
    # what makes the replayed model equal the current one - a nil would leave the option set.
    test "emits change_attribute when an attribute stops being unique" do
      replayed = model(%{MyApp.Task => %{attributes: [{:slug, :string, [unique: true]}]}})
      current = model(%{MyApp.Task => %{attributes: [{:slug, :string, []}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :slug,
                   changes: [unique: false]
                 }
               ],
               questions: []
             }
    end

    test "withholds member additions and deletions into a question" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:estimate, :integer, []},
              {:name, :string, []},
              {:notes, :string, []}
            ]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:estimate, :float, []}, {:title, :string, []}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :estimate,
                   changes: [type: :float]
                 }
               ],
               questions: [
                 %{
                   kind: :attributes,
                   entity: MyApp.Task,
                   deleted: [:name, :notes],
                   added: [:title],
                   hints: [],
                   withheld_ops: [
                     %{
                       op: :add_attribute,
                       entity: MyApp.Task,
                       name: :title,
                       type: :string,
                       opts: []
                     },
                     %{op: :delete_attribute, entity: MyApp.Task, name: :name},
                     %{op: :delete_attribute, entity: MyApp.Task, name: :notes}
                   ]
                 }
               ]
             }
    end

    test "hints the unambiguous same-type pair in a member question" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:name, :string, []}, {:priority, :integer, []}]
          }
        })

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert %{questions: [question]} = diff(replayed, current)

      assert question.hints == [{:rename, :name, :title}]
      assert question.deleted == [:name, :priority]
      assert question.added == [:title]
    end

    test "positions added enum values against the values already in place" do
      replayed =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:status, :enum, [values: [:draft, :todo, :doing, :done, :archived]]}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :add_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :draft,
                   opts: [before: :todo]
                 },
                 %{
                   op: :add_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :doing,
                   opts: [after: :todo]
                 },
                 %{
                   op: :add_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :archived,
                   opts: [after: :done]
                 }
               ],
               questions: []
             }
    end

    test "emits delete ops for removed enum values" do
      replayed =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]}
        })

      current =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :delete_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :doing
                 }
               ],
               questions: []
             }
    end

    test "emits a reorder op for an order-only enum change" do
      replayed =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :doing, :done]]}]}
        })

      current =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:done, :todo, :doing]]}]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :reorder_enum_values,
                   entity: MyApp.Task,
                   attribute: :status,
                   values: [:done, :todo, :doing]
                 }
               ],
               questions: []
             }
    end

    test "follows added enum values with a reorder when the surviving values also moved" do
      replayed =
        model(%{MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}})

      current =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:done, :doing, :todo]]}]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :add_enum_value,
                   entity: MyApp.Task,
                   attribute: :status,
                   value: :doing,
                   opts: [after: :done]
                 },
                 %{
                   op: :reorder_enum_values,
                   entity: MyApp.Task,
                   attribute: :status,
                   values: [:done, :doing, :todo]
                 }
               ],
               questions: []
             }
    end

    test "withholds enum value additions and deletions into a question" do
      replayed =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :done]]}]}
        })

      current =
        model(%{
          MyApp.Task => %{attributes: [{:status, :enum, [values: [:todo, :completed]]}]}
        })

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :enum_values,
                   entity: MyApp.Task,
                   attribute: :status,
                   deleted: [:done],
                   added: [:completed],
                   hints: [{:rename, :done, :completed}],
                   withheld_ops: [
                     %{
                       op: :delete_enum_value,
                       entity: MyApp.Task,
                       attribute: :status,
                       value: :done
                     },
                     %{
                       op: :add_enum_value,
                       entity: MyApp.Task,
                       attribute: :status,
                       value: :completed,
                       opts: [after: :todo]
                     }
                   ]
                 }
               ]
             }
    end

    test "emits global role ops" do
      replayed =
        model(%{}, %{
          MyApp.Roles.Admin => %{extends: []},
          MyApp.Roles.Owner => %{extends: []}
        })

      current =
        model(%{}, %{
          MyApp.Roles.Admin => %{extends: []},
          MyApp.Roles.Owner => %{extends: [MyApp.Roles.Admin]},
          MyApp.Roles.Support => %{extends: [MyApp.Roles.Admin]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :add_role,
                   role: MyApp.Roles.Support,
                   opts: [extends: [MyApp.Roles.Admin]]
                 },
                 %{
                   op: :change_role,
                   role: MyApp.Roles.Owner,
                   changes: [extends: [MyApp.Roles.Admin]]
                 }
               ],
               questions: []
             }
    end

    test "spells a global role losing its extends as the neutral value" do
      replayed = model(%{}, %{MyApp.Roles.Owner => %{extends: [MyApp.Roles.Admin]}})
      current = model(%{}, %{MyApp.Roles.Owner => %{extends: []}})

      assert diff(replayed, current) == %{
               ops: [%{op: :change_role, role: MyApp.Roles.Owner, changes: [extends: nil]}],
               questions: []
             }
    end

    test "withholds global role additions and deletions into a question" do
      replayed =
        model(%{}, %{
          MyApp.Roles.Moderator => %{extends: []},
          MyApp.Roles.Owner => %{extends: []}
        })

      current =
        model(%{}, %{
          MyApp.Roles.Maintainer => %{extends: []},
          MyApp.Roles.Owner => %{extends: [MyApp.Roles.Maintainer]}
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_role,
                   role: MyApp.Roles.Owner,
                   changes: [extends: [MyApp.Roles.Maintainer]]
                 }
               ],
               questions: [
                 %{
                   kind: :roles,
                   deleted: [MyApp.Roles.Moderator],
                   added: [MyApp.Roles.Maintainer],
                   hints: [{:rename, MyApp.Roles.Moderator, MyApp.Roles.Maintainer}],
                   withheld_ops: [
                     %{op: :add_role, role: MyApp.Roles.Maintainer, opts: []},
                     %{op: :delete_role, role: MyApp.Roles.Moderator}
                   ]
                 }
               ]
             }
    end
  end
end
