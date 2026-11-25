defmodule Hologram.Migration.DiffTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Diff

  alias Hologram.Entity.Model

  defp model(entities, roles \\ %{}) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry =
          Map.merge(
            %{attributes: [], relationships: [], roles: [], uniques: []},
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

    test "emits a created entity type's keys after its members" do
      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, MyApp.User, []}],
            roles: [{:editor, []}],
            uniques: [[:owner, :slug]]
          }
        })

      assert %{ops: ops, questions: []} = diff(Model.empty(), current)

      assert Enum.map(ops, & &1.op) == [
               :create_entity,
               :add_attribute,
               :add_relationship,
               :add_role,
               :add_unique
             ]

      assert List.last(ops) == %{op: :add_unique, entity: MyApp.Task, fields: [:owner, :slug]}
      assert Model.fold(Model.empty(), ops) == current
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
                   members: [{:add_attribute, :title, :string, []}],
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
            attributes: [{:estimate, :integer, [default: 0, min: 0]}],
            relationships: [{:tags, [MyApp.Tag], []}],
            roles: [{:owner, [granted_to: :creator]}]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:estimate, :float, [max: 10, min: 0]}],
            relationships: [{:tags, [MyApp.Label], [optional: true]}],
            roles: [{:owner, [extends: [:editor]]}]
          }
        })

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :estimate,
                   changes: [default: nil, max: 10, type: :float]
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
                   changes: [extends: [:editor], granted_to: nil]
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

    test "withholds a required to-one added to a surviving entity type into a question" do
      replayed = model(%{MyApp.Task => %{}, MyApp.User => %{}})

      current =
        model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, []}]}, MyApp.User => %{}})

      op = %{op: :add_relationship, entity: MyApp.Task, name: :owner, type: MyApp.User, opts: []}

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :fill,
                   entity: MyApp.Task,
                   attributes: [:owner],
                   members: [{:add_relationship, :owner, MyApp.User, []}],
                   withheld_ops: [op]
                 }
               ]
             }
    end

    test "withholds an attribute turning required with no default into a question" do
      replayed = model(%{MyApp.Task => %{attributes: [{:title, :string, [optional: true]}]}})
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      op = %{op: :change_attribute, entity: MyApp.Task, name: :title, changes: [optional: false]}

      assert diff(replayed, current) == %{
               ops: [],
               questions: [
                 %{
                   kind: :fill,
                   entity: MyApp.Task,
                   attributes: [:title],
                   members: [{:change_attribute, :title, [optional: false]}],
                   withheld_ops: [op]
                 }
               ]
             }
    end

    test "emits an attribute turning required with a default" do
      replayed =
        model(%{MyApp.Task => %{attributes: [{:title, :string, [default: "a", optional: true]}]}})

      current = model(%{MyApp.Task => %{attributes: [{:title, :string, [default: "a"]}]}})

      assert %{ops: [%{op: :change_attribute}], questions: []} = diff(replayed, current)
    end

    test "withholds a type change turning required, which its default can't fill" do
      replayed = model(%{MyApp.Task => %{attributes: [{:rank, :integer, [optional: true]}]}})
      current = model(%{MyApp.Task => %{attributes: [{:rank, :string, [default: "x"]}]}})

      assert %{
               ops: [],
               questions: [
                 %{
                   kind: :fill,
                   members: [
                     {:change_attribute, :rank, [default: "x", optional: false, type: :string]}
                   ]
                 }
               ]
             } = diff(replayed, current)
    end

    test "asks nothing of a to-many dropping optional" do
      replayed =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], [optional: true]}]}
        })

      current =
        model(%{MyApp.Tag => %{}, MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], []}]}})

      assert %{ops: [%{op: :change_relationship}], questions: []} = diff(replayed, current)
    end

    test "asks nothing of a to-many narrowing to a required to-one, which is refused" do
      replayed =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], [optional: true]}]}
        })

      current =
        model(%{MyApp.Tag => %{}, MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}})

      assert %{
               ops: [%{op: :change_relationship, changes: [optional: false, type: MyApp.Tag]}],
               questions: []
             } = diff(replayed, current)
    end

    test "withholds a to-one turning required into a question" do
      replayed =
        model(%{
          MyApp.Task => %{relationships: [{:owner, MyApp.User, [optional: true]}]},
          MyApp.User => %{}
        })

      current =
        model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, []}]}, MyApp.User => %{}})

      assert %{
               ops: [],
               questions: [
                 %{
                   kind: :fill,
                   attributes: [:owner],
                   members: [{:change_relationship, :owner, [optional: false]}]
                 }
               ]
             } = diff(replayed, current)
    end

    test "emits an optional to-one and a to-many without a question" do
      replayed = model(%{MyApp.Task => %{}, MyApp.User => %{}})

      current =
        model(%{
          MyApp.Task => %{
            relationships: [
              {:owner, MyApp.User, [optional: true]},
              {:watchers, [MyApp.User], []}
            ]
          },
          MyApp.User => %{}
        })

      assert %{ops: [%{op: :add_relationship}, %{op: :add_relationship}], questions: []} =
               diff(replayed, current)
    end

    test "restates a default equal in value when an attribute turns float" do
      replayed = model(%{MyApp.Task => %{attributes: [{:ratio, :integer, [default: 1]}]}})
      current = model(%{MyApp.Task => %{attributes: [{:ratio, :float, [default: 1.0]}]}})

      assert diff(replayed, current) === %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :ratio,
                   changes: [default: 1.0, type: :float]
                 }
               ],
               questions: []
             }
    end

    test "restates a default equal in value when an attribute turns integer" do
      replayed = model(%{MyApp.Task => %{attributes: [{:ratio, :float, [default: 1.0]}]}})
      current = model(%{MyApp.Task => %{attributes: [{:ratio, :integer, [default: 1]}]}})

      assert diff(replayed, current) === %{
               ops: [
                 %{
                   op: :change_attribute,
                   entity: MyApp.Task,
                   name: :ratio,
                   changes: [default: 1, type: :integer]
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

    test "emits change_relationship when a to-one relationship becomes unique" do
      replayed = model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, []}]}})
      current = model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, [unique: true]}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_relationship,
                   entity: MyApp.Task,
                   name: :owner,
                   changes: [unique: true]
                 }
               ],
               questions: []
             }
    end

    test "emits change_relationship when a to-one relationship stops being unique" do
      replayed = model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, [unique: true]}]}})
      current = model(%{MyApp.Task => %{relationships: [{:owner, MyApp.User, []}]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{
                   op: :change_relationship,
                   entity: MyApp.Task,
                   name: :owner,
                   changes: [unique: false]
                 }
               ],
               questions: []
             }
    end

    test "emits a deleted key before the members it names and an added key after them" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:kind, :slug], [:owner, :slug]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:code, :string, [optional: true]},
              {:kind, :string, []},
              {:slug, :string, []}
            ],
            uniques: [[:code, :slug]]
          }
        })

      assert %{ops: ops, questions: []} = diff(replayed, current)

      assert ops == [
               %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
               %{op: :delete_unique, entity: MyApp.Task, fields: [:owner, :slug]},
               %{
                 op: :add_attribute,
                 entity: MyApp.Task,
                 name: :code,
                 type: :string,
                 opts: [optional: true]
               },
               %{op: :delete_relationship, entity: MyApp.Task, name: :owner},
               %{op: :add_unique, entity: MyApp.Task, fields: [:code, :slug]}
             ]
    end

    test "emits ops the replay folds to the current model when keys and their fields change" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:owner, :slug]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, [MyApp.User], []}]
          }
        })

      assert %{ops: ops, questions: []} = diff(replayed, current)

      assert Enum.map(ops, & &1.op) == [:delete_unique, :change_relationship]
      assert Model.fold(replayed, ops) == current
    end

    test "emits a key whose field order changed as a delete and an add" do
      attributes = [{:kind, :string, []}, {:slug, :string, []}]
      replayed = model(%{MyApp.Task => %{attributes: attributes, uniques: [[:kind, :slug]]}})
      current = model(%{MyApp.Task => %{attributes: attributes, uniques: [[:slug, :kind]]}})

      assert diff(replayed, current) == %{
               ops: [
                 %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
                 %{op: :add_unique, entity: MyApp.Task, fields: [:slug, :kind]}
               ],
               questions: []
             }
    end

    test "withholds a key naming a member a question asks about, with its new spelling" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:name, :string, [optional: true]}],
            uniques: [[:kind, :name]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:title, :string, [optional: true]}],
            uniques: [[:kind, :title]]
          }
        })

      assert %{ops: [], questions: [question]} = diff(replayed, current)

      assert question.kind == :attributes

      assert question.withheld_ops == [
               %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :name]},
               %{
                 op: :add_attribute,
                 entity: MyApp.Task,
                 name: :title,
                 type: :string,
                 opts: [optional: true]
               },
               %{op: :delete_attribute, entity: MyApp.Task, name: :name},
               %{op: :add_unique, entity: MyApp.Task, fields: [:kind, :title]}
             ]

      assert Model.fold(replayed, question.withheld_ops) == current
    end

    test "leaves nothing to migrate once the question about a key's field is answered as a rename" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:owner, :slug]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:author, MyApp.User, []}],
            uniques: [[:author, :slug]]
          }
        })

      assert %{ops: [], questions: [%{kind: :relationships}]} = diff(replayed, current)

      answer = [
        %{op: :rename_relationship, entity: MyApp.Task, from: :owner, to: :author, line: 3}
      ]

      assert diff(Model.fold(replayed, answer), current) == %{ops: [], questions: []}
    end

    test "emits an added key naming what a question saw arrive when no deleted key is withheld" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:name, :string, []}, {:slug, :string, []}],
            uniques: [[:kind, :slug]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}, {:title, :string, []}],
            uniques: [[:slug, :title]]
          }
        })

      assert %{ops: ops, questions: [question]} = diff(replayed, current)

      assert ops == [
               %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
               %{op: :add_unique, entity: MyApp.Task, fields: [:slug, :title]}
             ]

      assert Enum.map(question.withheld_ops, & &1.op) == [:add_attribute, :delete_attribute]
    end

    test "rebuilds a key spelled the same when a field it names changes kind" do
      to_one =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :string, []}],
            relationships: [{:owner, MyApp.User, [optional: true]}],
            uniques: [[:owner, :slug]]
          }
        })

      attribute =
        model(%{
          MyApp.Task => %{
            attributes: [{:owner, :string, [optional: true]}, {:slug, :string, []}],
            uniques: [[:owner, :slug]]
          }
        })

      Enum.each([{to_one, attribute}, {attribute, to_one}], fn {replayed, current} ->
        assert %{ops: ops, questions: []} = diff(replayed, current)

        assert hd(ops) == %{op: :delete_unique, entity: MyApp.Task, fields: [:owner, :slug]}
        assert List.last(ops) == %{op: :add_unique, entity: MyApp.Task, fields: [:owner, :slug]}
        assert Model.fold(replayed, ops) == current
      end)
    end

    test "withholds a key into every question asking about a member it names" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [{:name, :string, [optional: true]}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:owner, :name]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:title, :string, [optional: true]}],
            relationships: [{:author, MyApp.User, []}],
            uniques: [[:author, :title]]
          }
        })

      assert %{ops: [], questions: [attributes, relationships]} = diff(replayed, current)

      delete_op = %{op: :delete_unique, entity: MyApp.Task, fields: [:owner, :name]}
      add_op = %{op: :add_unique, entity: MyApp.Task, fields: [:author, :title]}

      assert attributes.kind == :attributes
      assert hd(attributes.withheld_ops) == delete_op
      assert List.last(attributes.withheld_ops) == add_op

      assert relationships.kind == :relationships

      assert relationships.withheld_ops == [
               delete_op,
               %{
                 op: :add_relationship,
                 entity: MyApp.Task,
                 name: :author,
                 type: MyApp.User,
                 opts: []
               },
               %{op: :delete_relationship, entity: MyApp.Task, name: :owner},
               add_op
             ]
    end

    test "emits a key naming an attribute a fill question asks about" do
      replayed = model(%{MyApp.Task => %{attributes: [{:slug, :string, []}]}})

      current =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            uniques: [[:kind, :slug]]
          }
        })

      assert %{ops: ops, questions: [%{kind: :fill, withheld_ops: [%{op: :add_attribute}]}]} =
               diff(replayed, current)

      assert ops == [%{op: :add_unique, entity: MyApp.Task, fields: [:kind, :slug]}]
    end

    # The deleted role and the deleted enum value carry the names of the key's fields, so a
    # question of either kind taking the key by name would show.
    test "leaves key ops alone when the question asks about roles or enum values" do
      replayed =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:kind, :enum, [values: [:a, :kind]]},
              {:slug, :string, []}
            ],
            roles: [{:slug, []}],
            uniques: [[:kind, :slug]]
          }
        })

      current =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:kind, :enum, [values: [:a, :c]]},
              {:slug, :string, []}
            ],
            roles: [{:owner, []}],
            uniques: [[:slug, :kind]]
          }
        })

      assert %{ops: ops, questions: [first, second]} = diff(replayed, current)

      assert ops == [
               %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug]},
               %{op: :add_unique, entity: MyApp.Task, fields: [:slug, :kind]}
             ]

      assert Enum.sort([first.kind, second.kind]) == [:enum_values, :roles]
      assert first.deleted ++ second.deleted == [:kind, :slug]
      refute Enum.any?(first.withheld_ops ++ second.withheld_ops, &Map.has_key?(&1, :fields))
    end

    test "withholds a created entity type's keys with its other creation ops" do
      replayed =
        model(%{MyApp.Draft => %{attributes: [{:kind, :string, []}, {:slug, :string, []}]}})

      current =
        model(%{
          MyApp.Sketch => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            uniques: [[:kind, :slug]]
          }
        })

      assert %{ops: [], questions: [%{kind: :entities} = question]} = diff(replayed, current)

      assert %{op: :add_unique, entity: MyApp.Sketch, fields: [:kind, :slug]} in question.withheld_ops
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
