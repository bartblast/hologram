defmodule Hologram.Migration.RendererTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Renderer

  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Migration.Value
  alias Hologram.Test.Fixtures.Entity.Module14, as: UserEntity

  @moved_with_names "the next migration file, under the names things have there"

  # A term holding the user entity type designates it - the grant store derives from the
  # designation, so the tests that include it are the ones exercising the store.
  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry =
          Map.merge(%{attributes: [], relationships: [], roles: [], uniques: []}, entry_overrides)

        {entity_type, entry}
      end)

    user_entity = if Map.has_key?(entries, UserEntity), do: UserEntity

    %{entities: entries, roles: %{}, user_entity: user_entity}
  end

  defp op_kinds(ops), do: Enum.map(ops, & &1.op)

  describe "render/2, judging a file's backfills" do
    setup do
      [pre_model: model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})]
    end

    test "refuses a computed one naming a field the model lacks", %{pre_model: pre_model} do
      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :city,
        type: :string,
        opts: [optional: true, backfill: %Value{term: {:name, [:nope]}}],
        line: 7
      }

      assert_raise Hologram.CompileError, ~r/reads :nope, which MyApp.Task doesn't have/, fn ->
        render([op], pre_model)
      end
    end

    test "refuses a constant breaking a declared rule", %{pre_model: pre_model} do
      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :code,
        type: :string,
        opts: [max_length: 2, backfill: "long"],
        line: 7
      }

      assert_raise Hologram.CompileError, ~r/must be at most 2 characters/, fn ->
        render([op], pre_model)
      end
    end
  end

  describe "render/2, a constant uuid backfill" do
    test "encodes it whichever case the file wrote it in" do
      uuid = "018f0000-0000-7000-8000-00000000abcd"
      pre_model = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :external_id,
        type: :uuid,
        opts: [backfill: String.upcase(uuid)],
        line: 7
      }

      encoded = Codec.encode(uuid, :uuid)

      assert %{transactional: [%{op: :add_column, backfill: ^encoded} | _rest]} =
               render([op], pre_model)
    end
  end

  describe "render/2, a constant float backfill" do
    test "writes an integer the file gave as a float" do
      pre_model = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :weight,
        type: :float,
        opts: [backfill: 3],
        line: 7
      }

      assert %{transactional: [%{op: :add_column, backfill: backfill} | _rest]} =
               render([op], pre_model)

      assert backfill === 3.0
    end
  end

  describe "render/2, a computed backfill on an added attribute" do
    setup do
      pre_model =
        model(%{
          MyApp.Tag => %{attributes: [{:rank, :integer, []}]},
          MyApp.Task => %{
            attributes: [{:seats, :integer, []}, {:title, :string, []}],
            relationships: [{:tags, [MyApp.Tag], []}]
          }
        })

      [pre_model: pre_model]
    end

    defp add(name, opts, line \\ 7) do
      %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: name,
        type: :integer,
        opts: opts,
        line: line
      }
    end

    defp computed(name, term, opts \\ [optional: true], line \\ 7) do
      add(name, Keyword.put(opts, :backfill, %Value{term: term}), line)
    end

    test "gets a chunk of its own, cut before and after it", %{pre_model: pre_model} do
      ops = [
        add(:first, optional: true),
        computed(:second, {:name, [:first]}),
        add(:third, optional: true)
      ]

      assert %{transactional: transactional} = render(ops, pre_model)

      assert Enum.map(transactional, &{&1.op, &1.column}) == [
               {:add_column, "first"},
               {:add_column, "second"},
               {:fill_column, "second"},
               {:add_column, "third"}
             ]
    end

    test "renders over the row, leaving an optional column nullable", %{pre_model: pre_model} do
      assert %{transactional: [add_op, fill_op]} =
               render([computed(:copy, {:name, [:seats]})], pre_model)

      assert add_op.definition.null
      refute Map.has_key?(add_op, :backfill)

      assert %{
               op: :fill_column,
               table: "my_app_task",
               column: "copy",
               entity: MyApp.Task,
               member: :copy,
               nulls_only: false,
               required: false,
               sql: {~s("$r0"."seats"), "", []}
             } = fill_op

      refute Map.has_key?(fill_op, :mapping)
    end

    test "adds a required column nullable and tightens it after the fill, with no default", %{
      pre_model: pre_model
    } do
      op = computed(:copy, {:name, [:seats]}, default: 5)

      assert %{transactional: [add_op, fill_op, tighten_op]} = render([op], pre_model)

      assert add_op.definition.null
      refute Map.has_key?(add_op, :backfill)
      assert fill_op.required
      assert fill_op.rules == [default: 5]

      assert %{op: :alter_column, filled: true, before: %{null: true}, after: %{null: false}} =
               tighten_op

      refute Map.has_key?(tighten_op, :fill)
      refute Map.has_key?(tighten_op, :fill_companions)
    end

    test "fills a sort key this file added ahead of a fill ordering by it", %{
      pre_model: pre_model
    } do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Tag,
          name: :label,
          type: :string,
          opts: [optional: true],
          line: 6
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :top,
          type: :string,
          opts: [
            optional: true,
            backfill: %Value{term: {:most_common, {:relationship, [:tags]}, :label}}
          ],
          line: 7
        },
        %{op: :rename_attribute, entity: MyApp.Tag, from: :label, to: :name, line: 8}
      ]

      %{transactional: transactional} = render(ops, pre_model)

      position = Enum.find_index(transactional, &(&1.op == :fill_column))
      companion_fill = Enum.at(transactional, position - 1)

      assert %{
               op: :fill_companions,
               columns: [%{op: :add_column, table: "my_app_tag", column: "label_$sort"}]
             } = companion_fill

      assert Enum.any?(
               companion_fill.mapping[MyApp.Tag].columns,
               &(&1.name == "label_$sort")
             )
    end

    test "doesn't fill a sort key that stood before the file", %{pre_model: pre_model} do
      with_label =
        put_in(pre_model, [:entities, MyApp.Tag, :attributes], [
          {:label, :string, []},
          {:rank, :integer, []}
        ])

      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :top,
        type: :string,
        opts: [
          optional: true,
          backfill: %Value{term: {:most_common, {:relationship, [:tags]}, :label}}
        ],
        line: 7
      }

      refute Enum.any?(render([op], with_label).transactional, &(&1.op == :fill_companions))
    end
  end

  describe "render/2, a cut leaving a delete apart from its cleanup" do
    setup do
      pre_model =
        model(%{
          MyApp.Place => %{},
          MyApp.Task => %{
            attributes: [{:seats, :integer, []}],
            relationships: [{:place, MyApp.Place, [optional: true]}]
          }
        })

      [pre_model: pre_model]
    end

    test "refuses a deleted target whose inbound relationship goes below the cut", %{
      pre_model: pre_model
    } do
      ops = [
        %{op: :delete_entity, entity: MyApp.Place, line: 5},
        computed(:copy, {:name, [:seats]}),
        %{op: :delete_relationship, entity: MyApp.Task, name: :place, line: 9}
      ]

      assert_raise Hologram.CompileError,
                   ~r/apply apart from the ops around them: add_attribute :copy on MyApp.Task \(line 7\)/,
                   fn -> render(ops, pre_model) end
    end

    test "refuses recreating a target an inbound relationship still points to", %{
      pre_model: pre_model
    } do
      ops = [
        %{op: :delete_entity, entity: MyApp.Place, line: 5},
        %{op: :create_entity, entity: MyApp.Place, line: 6}
      ]

      expected_msg =
        "MyApp.Place is deleted and created again in this file while :place on MyApp.Task " <>
          "still targets it - the delete applies apart from the create, so delete the " <>
          "relationship before deleting MyApp.Place, and add it again after creating MyApp.Place"

      assert_raise Hologram.CompileError, expected_msg, fn -> render(ops, pre_model) end
    end

    test "names every recreated target an inbound relationship still points to" do
      pre_model =
        model(%{
          MyApp.Place => %{},
          MyApp.Tag => %{},
          MyApp.Task => %{
            relationships: [
              {:place, MyApp.Place, [optional: true]},
              {:tags, [MyApp.Tag], []}
            ]
          }
        })

      ops = [
        %{op: :delete_entity, entity: MyApp.Place, line: 5},
        %{op: :delete_entity, entity: MyApp.Tag, line: 6},
        %{op: :create_entity, entity: MyApp.Place, line: 7},
        %{op: :create_entity, entity: MyApp.Tag, line: 8}
      ]

      expected_msg =
        "MyApp.Place is deleted and created again in this file while :place on MyApp.Task " <>
          "still targets it - the delete applies apart from the create, so delete the " <>
          "relationship before deleting MyApp.Place, and add it again after creating " <>
          "MyApp.Place; MyApp.Tag is deleted and created again in this file while :tags on " <>
          "MyApp.Task still targets it - the delete applies apart from the create, so delete " <>
          "the relationship before deleting MyApp.Tag, and add it again after creating MyApp.Tag"

      assert_raise Hologram.CompileError, expected_msg, fn -> render(ops, pre_model) end
    end

    test "names each inbound relationship of a recreated target" do
      pre_model =
        model(%{
          MyApp.Place => %{},
          MyApp.Task => %{
            relationships: [
              {:home, MyApp.Place, [optional: true]},
              {:place, MyApp.Place, [optional: true]}
            ]
          }
        })

      ops = [
        %{op: :delete_entity, entity: MyApp.Place, line: 5},
        %{op: :create_entity, entity: MyApp.Place, line: 6}
      ]

      expected_msg =
        "MyApp.Place is deleted and created again in this file while :home on MyApp.Task, " <>
          ":place on MyApp.Task still target it - the delete applies apart from the create, " <>
          "so delete the relationships before deleting MyApp.Place, and add them again after " <>
          "creating MyApp.Place"

      assert_raise Hologram.CompileError, expected_msg, fn -> render(ops, pre_model) end
    end

    test "accepts the recreate with the inbound relationship deleted and added again", %{
      pre_model: pre_model
    } do
      ops = [
        %{op: :delete_relationship, entity: MyApp.Task, name: :place, line: 5},
        %{op: :delete_entity, entity: MyApp.Place, line: 6},
        %{op: :create_entity, entity: MyApp.Place, line: 7},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :place,
          type: MyApp.Place,
          opts: [optional: true],
          line: 8
        }
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end

    test "accepts the same file with the cleanup moved above the cut", %{pre_model: pre_model} do
      ops = [
        %{op: :delete_relationship, entity: MyApp.Task, name: :place, line: 5},
        %{op: :delete_entity, entity: MyApp.Place, line: 6},
        computed(:copy, {:name, [:seats]})
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end

    test "refuses a designation moving apart from its grant deletes" do
      pre_model =
        model(%{
          UserEntity => %{},
          MyApp.Member => %{},
          MyApp.Task => %{attributes: [{:seats, :integer, []}]}
        })

      ops = [
        %{op: :delete_role_grants, line: 5},
        computed(:copy, {:name, [:seats]}),
        %{op: :designate_user_entity, entity: MyApp.Member, line: 9}
      ]

      assert_raise Hologram.CompileError, ~r/apply apart from the ops around them/, fn ->
        render(ops, pre_model)
      end

      moved = [Enum.at(ops, 0), Enum.at(ops, 2), Enum.at(ops, 1)]

      assert %{transactional: _transactional} = render(moved, pre_model)
    end

    test "refuses a computed add above the delete of the to-one holding its column", %{
      pre_model: pre_model
    } do
      ops = [
        computed(:place_id, {:name, [:seats]}),
        %{op: :delete_relationship, entity: MyApp.Task, name: :place, line: 9}
      ]

      assert_raise Hologram.CompileError,
                   ~r/apply apart from the ops around them: add_attribute :place_id.*colliding/s,
                   fn -> render(ops, pre_model) end

      assert %{transactional: _transactional} = render(Enum.reverse(ops), pre_model)
    end

    test "names every cut, since any of them may part the pair" do
      pre_model =
        model(%{
          UserEntity => %{},
          MyApp.Member => %{},
          MyApp.Task => %{attributes: [{:seats, :integer, []}]}
        })

      ops = [
        %{op: :delete_role_grants, line: 5},
        computed(:copy, {:name, [:seats]}, [optional: true], 7),
        %{op: :designate_user_entity, entity: MyApp.Member, line: 9},
        computed(:other, {:name, [:seats]}, [optional: true], 11)
      ]

      assert_raise Hologram.CompileError, ~r/:copy on MyApp.Task \(line 7\), .*\(line 11\)/, fn ->
        render(ops, pre_model)
      end
    end

    test "refuses a relationship above a cut whose target is created below it", %{
      pre_model: pre_model
    } do
      add_zone = %{
        op: :add_relationship,
        entity: MyApp.Task,
        name: :zone,
        type: MyApp.Zone,
        opts: [optional: true],
        line: 5
      }

      create_zone = %{op: :create_entity, entity: MyApp.Zone, line: 9}
      fill = computed(:copy, {:name, [:seats]})

      assert_raise Hologram.CompileError, ~r/:zone on MyApp.Task targets MyApp.Zone/, fn ->
        render([add_zone, fill, create_zone], pre_model)
      end

      assert %{transactional: _transactional} =
               render([create_zone, add_zone, fill], pre_model)
    end

    test "refuses a default the file adds to its enum after a cut", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [values: [:a], optional: true],
          line: 3
        },
        computed(:copy, {:name, [:seats]}),
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 8
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :fresh],
          line: 9
        }
      ]

      error =
        assert_raise Hologram.CompileError,
                     ~r/the default "fresh" of column "grade".*#1687/,
                     fn ->
                       render(ops, pre_model)
                     end

      assert String.ends_with?(error.message, @moved_with_names)
    end

    test "marks a tightening filling a value the file adds below a cut" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:grade, :enum, [optional: true, values: [:a]]},
              {:seats, :integer, [optional: true]}
            ]
          }
        })

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :fresh],
          line: 3
        },
        computed(:copy, {:name, [:seats]}),
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 8
        }
      ]

      %{transactional: rendered} = render(ops, pre_model)

      assert %{default_held: false, fill: "fresh"} =
               Enum.find(rendered, &(&1.op == :alter_column and &1.column == "grade"))
    end

    test "marks a tightening filling a value the file adds below a rename" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:grade, :enum, [optional: true, values: [:a]]},
              {:seats, :integer, [optional: true]}
            ]
          }
        })

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :fresh],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :seats, to: :places, line: 4},
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 5
        }
      ]

      %{transactional: rendered} = render(ops, pre_model)

      assert %{default_held: false, fill: "fresh"} =
               Enum.find(rendered, &(&1.op == :alter_column and &1.column == "grade"))
    end

    test "passes a fill of a value whose label a later rename frees and an add takes" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:grade, :enum, [optional: true, values: [:a, :b]]},
              {:seats, :integer, [optional: true]}
            ]
          }
        })

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :a],
          line: 3
        },
        computed(:copy, {:name, [:seats]}),
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          from: :a,
          to: :z,
          line: 8
        },
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :a,
          opts: [],
          line: 9
        }
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end

    test "refuses a required add filling a value the file adds below a cut" do
      pre_model =
        model(%{MyApp.Task => %{attributes: [{:seats, :integer, [optional: true]}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [default: :fresh, values: [:a]],
          line: 3
        },
        computed(:copy, {:name, [:seats]}),
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 8
        }
      ]

      expected_msg =
        ~s(the default "fresh" of column "grade" on table "my_app_task" is an enum value ) <>
          "its type doesn't hold yet when the column fills - list the value in the values: of " <>
          "the op adding the attribute, and drop the op adding it to the type further down - " <>
          "or, when a rename further down gives the value its label, list the label in place " <>
          "of the value renamed and drop the rename"

      assert_raise Hologram.CompileError, expected_msg, fn -> render(ops, pre_model) end
    end

    test "refuses a required add filling a label a rename gives a value below a cut" do
      pre_model =
        model(%{MyApp.Task => %{attributes: [{:seats, :integer, [optional: true]}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [default: :live, values: [:draft]],
          line: 3
        },
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          from: :draft,
          to: :live,
          line: 8
        }
      ]

      expected_msg =
        ~s(the default "live" of column "grade" on table "my_app_task" is an enum value ) <>
          "its type doesn't hold yet when the column fills - list the value in the values: of " <>
          "the op adding the attribute, and drop the op adding it to the type further down - " <>
          "or, when a rename further down gives the value its label, list the label in place " <>
          "of the value renamed and drop the rename"

      assert_raise Hologram.CompileError, expected_msg, fn -> render(ops, pre_model) end
    end

    test "accepts the same add with the renamed value's label listed in its values" do
      pre_model =
        model(%{MyApp.Task => %{attributes: [{:seats, :integer, [optional: true]}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [default: :live, values: [:live]],
          line: 3
        }
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end

    test "accepts the same add with the value listed in its values" do
      pre_model =
        model(%{MyApp.Task => %{attributes: [{:seats, :integer, [optional: true]}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [default: :fresh, values: [:a, :fresh]],
          line: 3
        },
        computed(:copy, {:name, [:seats]})
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end
  end

  describe "render/2, deleting and adding one name in a file" do
    setup do
      pre_model =
        model(%{
          MyApp.Place => %{},
          MyApp.Task => %{
            attributes: [{:kind, :enum, [values: [:a, :b]]}, {:title, :string, []}],
            relationships: [{:place, MyApp.Place, [optional: true]}, {:tags, [MyApp.Place], []}]
          }
        })

      [pre_model: pre_model]
    end

    defp delete(kind, name), do: %{op: kind, entity: MyApp.Task, name: name, line: 5}

    defp add_member(kind, name, type, opts) do
      %{op: kind, entity: MyApp.Task, name: name, type: type, opts: opts, line: 6}
    end

    test "drops the attribute's column and adds a new one", %{pre_model: pre_model} do
      ops = [
        delete(:delete_attribute, :title),
        add_member(:add_attribute, :title, :string, optional: true, backfill: "new")
      ]

      %{transactional: transactional} = render(ops, pre_model)
      changes = for %{op: op, column: "title"} = change <- transactional, do: {op, change}

      assert [{:drop_column, _dropped}, {:add_column, %{backfill: "new"}}] = changes
    end

    test "drops an enum's type along with its column", %{pre_model: pre_model} do
      ops = [
        delete(:delete_attribute, :kind),
        add_member(:add_attribute, :kind, :enum, values: [:a, :b, :c], optional: true)
      ]

      transactional = render(ops, pre_model).transactional
      kinds = op_kinds(transactional)

      changes =
        for %{op: op, enum_type: "my_app_task_kind_$enum"} <- transactional,
            op in [:create_enum_type, :drop_enum_type],
            do: op

      assert changes == [:drop_enum_type, :create_enum_type]
      refute :add_enum_value in kinds
      refute :alter_column in kinds
    end

    test "drops a to-one's column and adds a new one", %{pre_model: pre_model} do
      ops = [
        delete(:delete_relationship, :place),
        add_member(:add_relationship, :place, MyApp.Place, optional: true)
      ]

      changes =
        for %{op: op, column: "place_id"} <- render(ops, pre_model).transactional,
            op in [:add_column, :drop_column],
            do: op

      assert changes == [:drop_column, :add_column]
    end

    test "drops a to-many's join table and creates a new one", %{pre_model: pre_model} do
      ops = [
        delete(:delete_relationship, :tags),
        add_member(:add_relationship, :tags, [MyApp.Place], [])
      ]

      changes =
        for %{op: op, table: "my_app_task_tags_$join"} <- render(ops, pre_model).transactional,
            op in [:create_table, :drop_table],
            do: op

      assert changes == [:drop_table, :create_table]
    end

    test "treats an attribute taking a deleted to-one's column as the same name", %{
      pre_model: pre_model
    } do
      ops = [
        delete(:delete_relationship, :place),
        add_member(:add_attribute, :place_id, :uuid, optional: true)
      ]

      changes =
        for %{op: op, column: "place_id"} <- render(ops, pre_model).transactional, do: op

      assert changes == [:drop_column, :add_column]
    end

    test "drops a recreated entity's table" do
      pre_model = model(%{MyApp.Place => %{attributes: [{:name, :string, []}]}})

      ops = [
        %{op: :delete_entity, entity: MyApp.Place, line: 5},
        %{op: :create_entity, entity: MyApp.Place, line: 6},
        %{
          op: :add_attribute,
          entity: MyApp.Place,
          name: :name,
          type: :string,
          opts: [optional: true],
          line: 7
        }
      ]

      assert [:drop_table, :create_table] =
               ops
               |> render(pre_model)
               |> Map.fetch!(:transactional)
               |> op_kinds()
               |> Enum.filter(&(&1 in [:drop_table, :create_table]))
    end

    test "drops and adds a shared column with the add written above the delete", %{
      pre_model: pre_model
    } do
      ops = [
        add_member(:add_attribute, :place_id, :uuid,
          optional: true,
          backfill: "018f0000-0000-7000-8000-000000000000"
        ),
        delete(:delete_relationship, :place)
      ]

      changes =
        for %{op: op, column: "place_id"} <- render(ops, pre_model).transactional,
            op in [:add_column, :alter_column, :drop_column],
            do: op

      assert changes == [:drop_column, :add_column]
    end

    test "finds the column of a to-one whose long name the mapper shortens" do
      long_name =
        "a"
        |> String.duplicate(61)
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        |> String.to_atom()

      place = {long_name, MyApp.Place, [optional: true]}

      pre_model =
        model(%{MyApp.Place => %{}, MyApp.Task => %{relationships: [place]}})

      column =
        pre_model
        |> Mapper.derive_from_model!()
        |> Map.fetch!(MyApp.Task)
        |> Map.fetch!(:columns)
        |> Enum.find(&(&1.source == {:relationship, long_name}))
        |> Map.fetch!(:name)

      refute column == "#{long_name}_id"

      ops = [
        delete(:delete_relationship, long_name),
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        add_member(:add_attribute, String.to_atom(column), :uuid, optional: true)
      ]

      changes =
        for %{op: op, column: ^column} <- render(ops, pre_model).transactional,
            op in [:add_column, :alter_column, :drop_column],
            do: op

      assert changes == [:drop_column, :add_column]
    end

    test "doesn't take a to-many for the holder of a column named like it", %{
      pre_model: pre_model
    } do
      above = [
        add_member(:add_attribute, :tags_id, :uuid, optional: true),
        delete(:delete_relationship, :tags)
      ]

      below = Enum.reverse(above)

      for ops <- [above, below] do
        kinds = op_kinds(render(ops, pre_model).transactional)

        assert :add_column in kinds
        assert :drop_table in kinds
      end
    end

    test "drops the table of an entity type another takes the table name of" do
      pre_model = model(%{MyApp.TaskItem => %{attributes: [{:name, :string, []}]}})

      ops = [
        %{op: :delete_entity, entity: MyApp.TaskItem, line: 5},
        %{op: :create_entity, entity: MyApp.Task.Item, line: 6},
        %{
          op: :add_attribute,
          entity: MyApp.Task.Item,
          name: :name,
          type: :string,
          opts: [optional: true],
          line: 7
        }
      ]

      kinds = op_kinds(render(ops, pre_model).transactional)

      assert Enum.filter(kinds, &(&1 in [:alter_column, :create_table, :drop_table])) ==
               [:drop_table, :create_table]

      assert_raise Hologram.CompileError, ~r/apply apart from the ops around them/, fn ->
        render([Enum.at(ops, 1), Enum.at(ops, 2), Enum.at(ops, 0)], pre_model)
      end
    end

    test "drops a join table another entity type's to-many takes the name of" do
      pre_model =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:item_tags, [MyApp.Tag], []}]},
          MyApp.Task.Item => %{}
        })

      ops = [
        %{op: :delete_relationship, entity: MyApp.Task, name: :item_tags, line: 5},
        %{
          op: :add_relationship,
          entity: MyApp.Task.Item,
          name: :tags,
          type: [MyApp.Tag],
          opts: [],
          line: 6
        }
      ]

      changes =
        for %{op: op, table: "my_app_task_item_tags_$join"} <-
              render(ops, pre_model).transactional,
            op in [:create_table, :drop_table],
            do: op

      assert changes == [:drop_table, :create_table]
    end

    test "leaves a delete and an add of different names in one chunk", %{pre_model: pre_model} do
      ops = [
        add_member(:add_attribute, :subtitle, :string, optional: true),
        delete(:delete_attribute, :title)
      ]

      # One chunk's diff drops before it adds, while chunks apart would keep the add first.
      assert op_kinds(render(ops, pre_model).transactional) ==
               List.duplicate(:drop_column, 3) ++ List.duplicate(:add_column, 3)
    end
  end

  describe "render/2, a constant fill of an enum value the file deletes" do
    setup do
      [pre_model: model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})]
    end

    defp filled_phase(values) do
      %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :phase,
        type: :enum,
        opts: [values: values, backfill: :live],
        line: 5
      }
    end

    defp phase_value_op(kind, value) do
      %{op: kind, entity: MyApp.Task, attribute: :phase, value: value, opts: [], line: 6}
    end

    test "refuses a backfill of an added member whose value the file deletes after it", %{
      pre_model: pre_model
    } do
      ops = [filled_phase([:draft, :live]), phase_value_op(:delete_enum_value, :live)]

      error = assert_raise Hologram.CompileError, fn -> render(ops, pre_model) end

      assert error.message ==
               ~s(the value "live" filling column "phase" on table "my_app_task" is an enum ) <>
                 "value this file deletes from its type, which no longer holds it where the " <>
                 "fill runs, so the fill would fail on every row - fill with a value the type " <>
                 "keeps, or keep the value"
    end

    test "leaves a tightening's default to where it fills rows, after the file rebuilds its type" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:grade, :enum, [optional: true, values: [:a, :b]]},
              {:seats, :integer, [optional: true]}
            ]
          }
        })

      ops = [
        %{op: :delete_enum_value, entity: MyApp.Task, attribute: :grade, value: :b, line: 2},
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, default: :fresh],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :seats, to: :places, line: 4},
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :grade,
          value: :fresh,
          opts: [],
          line: 5
        }
      ]

      %{transactional: rendered} = render(ops, pre_model)

      assert %{default_held: false, fill: "fresh"} =
               Enum.find(rendered, &(&1.op == :alter_column and &1.column == "grade"))
    end

    test "keeps a backfill whose value the file deletes and adds back", %{pre_model: pre_model} do
      ops = [
        filled_phase([:draft, :live]),
        phase_value_op(:delete_enum_value, :live),
        phase_value_op(:add_enum_value, :live)
      ]

      assert [%{op: :create_enum_type, values: values}, %{op: :add_column, backfill: "live"}] =
               render(ops, pre_model).transactional

      assert "live" in values
    end

    test "keeps a backfill whose value the file renames after it", %{pre_model: pre_model} do
      ops = [
        filled_phase([:draft, :live]),
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :phase,
          from: :live,
          to: :on,
          line: 6
        }
      ]

      assert [_create, %{op: :add_column, backfill: "live"}, %{op: :rename_enum_value}] =
               render(ops, pre_model).transactional
    end
  end

  describe "render/2, a fill using an enum value the file adds" do
    setup do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:kind, :enum, [values: [:draft, :live]]},
              {:state, :enum, [values: [:draft, :fresh]]}
            ]
          }
        })

      [pre_model: pre_model]
    end

    defp add_value(attribute, value) do
      %{
        op: :add_enum_value,
        entity: MyApp.Task,
        attribute: attribute,
        value: value,
        opts: [],
        line: 5
      }
    end

    defp enum_fill(name, term, values) do
      %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: name,
        type: :enum,
        opts: [values: values, optional: true, backfill: %Value{term: term}],
        line: 7
      }
    end

    defp rename_attribute(from, to) do
      %{op: :rename_attribute, entity: MyApp.Task, from: from, to: to, line: 6}
    end

    @refusal ~r/uses the enum value "fresh", which this file adds to its type .*#1687/

    test "refuses a literal of the added value", %{pre_model: pre_model} do
      ops = [
        add_value(:kind, :fresh),
        enum_fill(
          :copy,
          {:coalesce, [{:name, [:kind]}, {:value, :fresh}]},
          [:draft, :live, :fresh]
        )
      ]

      error = assert_raise Hologram.CompileError, @refusal, fn -> render(ops, pre_model) end

      assert error.message =~
               "so move the op adding the member, with its backfill, to " <> @moved_with_names
    end

    test "follows a value renamed after its add", %{pre_model: pre_model} do
      ops = [
        add_value(:kind, :temp),
        %{
          op: :rename_enum_value,
          entity: MyApp.Task,
          attribute: :kind,
          from: :temp,
          to: :fresh,
          line: 6
        },
        enum_fill(:copy, {:coalesce, [{:name, [:kind]}, {:value, :fresh}]}, [
          :draft,
          :live,
          :fresh
        ])
      ]

      assert_raise Hologram.CompileError, @refusal, fn -> render(ops, pre_model) end
    end

    test "follows the type through an attribute rename", %{pre_model: pre_model} do
      ops = [
        add_value(:kind, :fresh),
        rename_attribute(:kind, :sort),
        enum_fill(:copy, {:coalesce, [{:name, [:sort]}, {:value, :fresh}]}, [
          :draft,
          :live,
          :fresh
        ])
      ]

      assert_raise Hologram.CompileError, @refusal, fn -> render(ops, pre_model) end
    end

    test "refuses a value added after a rename split the type's own chunk", %{
      pre_model: pre_model
    } do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [values: [:a], optional: true],
          line: 3
        },
        rename_attribute(:state, :status),
        add_value(:grade, :fresh),
        enum_fill(:copy, {:coalesce, [{:name, [:grade]}, {:value, :fresh}]}, [:a, :fresh])
      ]

      assert_raise Hologram.CompileError, @refusal, fn -> render(ops, pre_model) end
    end

    test "accepts a value on a type the same chunk created", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :grade,
          type: :enum,
          opts: [values: [:a], optional: true],
          line: 3
        },
        add_value(:grade, :fresh),
        enum_fill(:copy, {:coalesce, [{:name, [:grade]}, {:value, :fresh}]}, [:a, :fresh])
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end

    test "refuses a constant tightening using the added value" do
      pre_model =
        model(%{
          MyApp.Task => %{attributes: [{:kind, :enum, [optional: true, values: [:draft]]}]}
        })

      ops = [
        add_value(:kind, :fresh),
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :kind,
          changes: [optional: false, backfill: :fresh],
          line: 7
        }
      ]

      error =
        assert_raise Hologram.CompileError,
                     ~r/the backfill "fresh" of column "kind".*#1687/,
                     fn -> render(ops, pre_model) end

      assert String.ends_with?(error.message, @moved_with_names)
    end

    test "refuses a copy into a standing type that the file added a value to" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:grade, :enum, [optional: true, values: [:a]]},
              {:kind, :enum, [values: [:a, :fresh]]}
            ]
          }
        })

      ops = [
        add_value(:grade, :fresh),
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :grade,
          changes: [optional: false, backfill: %Value{term: {:name, [:kind]}}],
          line: 7
        }
      ]

      error = assert_raise Hologram.CompileError, @refusal, fn -> render(ops, pre_model) end

      assert error.message =~
               "so move the op making the member required, with its backfill, to " <>
                 @moved_with_names
    end

    test "accepts a value a rebuild has carried into a new type", %{pre_model: pre_model} do
      # The rename cuts the chunk, so the add runs as its own step before the rebuild.
      ops = [
        add_value(:kind, :fresh),
        rename_attribute(:state, :phase),
        %{
          op: :reorder_enum_values,
          entity: MyApp.Task,
          attribute: :kind,
          values: [:fresh, :live, :draft],
          line: 6
        },
        enum_fill(:copy, {:coalesce, [{:name, [:kind]}, {:value, :fresh}]}, [
          :draft,
          :live,
          :fresh
        ])
      ]

      kinds = op_kinds(render(ops, pre_model).transactional)

      assert Enum.filter(kinds, &(&1 in [:add_enum_value, :rebuild_enum_type, :fill_column])) ==
               [:add_enum_value, :rebuild_enum_type, :fill_column]
    end

    test "accepts a value that was on the type already", %{pre_model: pre_model} do
      ops = [
        add_value(:kind, :fresh),
        enum_fill(:copy, {:coalesce, [{:name, [:kind]}, {:value, :live}]}, [
          :draft,
          :live,
          :fresh
        ])
      ]

      assert %{transactional: _transactional} = render(ops, pre_model)
    end
  end

  describe "render/2, a backfill on a tightening" do
    setup do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [
              {:notes, :string, [optional: true]},
              {:rank, :integer, [optional: true]}
            ]
          }
        })

      [pre_model: pre_model]
    end

    defp tighten(name, backfill, line \\ 7) do
      %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: name,
        changes: [optional: false, backfill: backfill],
        line: line
      }
    end

    test "stamps a constant as the fill, naming the companions", %{pre_model: pre_model} do
      %{transactional: [alter]} = render([tighten(:notes, "none")], pre_model)

      assert %{
               op: :alter_column,
               column: "notes",
               fill: "none",
               fill_source: :backfill,
               fill_companions: [sort_key: "notes_$sort", search_key: "notes_$search"]
             } = alter
    end

    test "wins over the declared default", %{pre_model: pre_model} do
      op = put_in(tighten(:notes, "none").changes[:default], "other")

      assert %{transactional: [%{fill: "none"}]} = render([op], pre_model)
    end

    test "fills the rows holding nil before a computed tightening", %{pre_model: pre_model} do
      op = tighten(:notes, %Value{term: {:coalesce, [{:name, [:notes]}, {:value, ""}]}})

      assert %{transactional: [fill, alter]} = render([op], pre_model)

      assert %{
               op: :fill_column,
               column: "notes",
               companions: [sort_key: "notes_$sort", search_key: "notes_$search"],
               nulls_only: true,
               required: true
             } = fill

      assert %{op: :alter_column, column: "notes", filled: true} = alter
      refute Map.has_key?(alter, :fill)
    end

    test "fills a relationship whose op states the target it has" do
      pre_model =
        model(%{
          MyApp.Task => %{
            relationships: [
              {:creator, MyApp.User, []},
              {:owner, MyApp.User, [optional: true]}
            ]
          },
          MyApp.User => %{}
        })

      tighten = fn backfill ->
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :owner,
          changes: [type: MyApp.User, optional: false, backfill: backfill],
          line: 3
        }
      end

      uuid = "018f0000-0000-7000-8000-000000000000"

      assert %{transactional: [%{op: :alter_column, fill: <<_id::128>>, fill_source: :backfill}]} =
               render([tighten.(uuid)], pre_model)

      computed = tighten.(%Value{term: {:name, [:creator_id]}})

      assert %{transactional: [%{op: :fill_column, column: "owner_id"}, alter]} =
               render([computed], pre_model)

      assert %{op: :alter_column, column: "owner_id", filled: true} = alter
    end

    test "renders an attribute cast in a chunk led by a relationship change as no retarget" do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [{:seats, :integer, []}],
            relationships: [{:owner, MyApp.User, [optional: true]}]
          },
          MyApp.User => %{}
        })

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :owner,
          changes: [optional: false],
          line: 3
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :seats,
          changes: [type: :string],
          line: 4
        },
        %{op: :create_entity, entity: MyApp.Place, line: 5}
      ]

      %{transactional: transactional} = render(ops, pre_model)

      assert %{op: :create_table} = Enum.find(transactional, &(&1[:table] == "my_app_place"))

      assert %{after: %{null: false}} =
               Enum.find(transactional, &(&1.op == :alter_column and &1.column == "owner_id"))

      assert %{after: %{type: "text"}} =
               Enum.find(transactional, &(&1.op == :alter_column and &1.column == "seats"))
    end

    test "renders a required retarget widened by the next op, which drops the column" do
      pre_model =
        model(%{
          MyApp.Admin => %{},
          MyApp.Task => %{relationships: [{:reviewer, MyApp.User, [optional: true]}]},
          MyApp.User => %{}
        })

      change = fn changes, line ->
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :reviewer,
          changes: changes,
          line: line
        }
      end

      ops = [
        change.([type: MyApp.Admin, optional: false], 3),
        change.([type: [MyApp.Admin]], 4)
      ]

      %{transactional: transactional} = render(ops, pre_model)

      assert [
               %{op: :drop_foreign_key, table: "my_app_task"},
               %{op: :alter_column, column: "reviewer_id", after: %{null: false}},
               %{op: :add_foreign_key, column: "reviewer_id", references: "my_app_admin"},
               %{op: :create_table, table: "my_app_task_reviewer_$join"},
               %{op: :add_foreign_key, column: "source_id", references: "my_app_task"},
               %{op: :add_foreign_key, column: "target_id", references: "my_app_admin"},
               %{
                 op: :widen_to_many,
                 column: "reviewer_id",
                 join_table: "my_app_task_reviewer_$join"
               },
               %{op: :drop_foreign_key, constraint: "my_app_task_reviewer_id_$fk"},
               %{op: :drop_column, table: "my_app_task", column: "reviewer_id"}
             ] = transactional
    end

    test "keeps a constant tightening apart from a type change beside it", %{
      pre_model: pre_model
    } do
      change = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :rank,
        changes: [type: :string],
        line: 6
      }

      %{transactional: ops} = render([change, tighten(:rank, "0")], pre_model)

      assert [
               %{op: :alter_column, before: %{type: "int8"}, after: %{type: "text", null: true}},
               %{op: :alter_column, before: %{type: "text"}, fill: "0"}
             ] = Enum.filter(ops, &(&1.op == :alter_column))
    end
  end

  describe "render/2, an added relationship's options" do
    setup do
      pre_model =
        model(%{
          MyApp.Task => %{
            attributes: [{:notes, :string, [optional: true]}],
            relationships: [{:owner, MyApp.Task, [optional: true]}]
          }
        })

      [pre_model: pre_model]
    end

    test "still renders an added relationship whose options are a map", %{pre_model: pre_model} do
      op = %{
        op: :add_relationship,
        entity: MyApp.Task,
        name: :parent,
        type: MyApp.Task,
        opts: %{optional: true},
        line: 7
      }

      assert %{
               transactional: [
                 %{op: :add_column, column: "parent_id", definition: %{null: true}} | _rest
               ]
             } = render([op], pre_model)
    end

    test "still renders a constant one on an added attribute", %{pre_model: pre_model} do
      op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :summary,
        type: :string,
        opts: [backfill: "none"],
        line: 7
      }

      assert %{transactional: [%{op: :add_column, backfill: "none"} | _rest]} =
               render([op], pre_model)
    end
  end

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
               "$revisions",
               "created_at",
               "id",
               "server_created_at",
               "server_created_seq",
               "server_updated_at",
               "server_updated_seq",
               "title",
               "title_$search",
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

    test "carries a required attribute's declared default as its backfill" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [default: 5],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :priority, to: :rank, line: 4}
      ]

      result = render(ops, pre)

      assert %{column: "priority", backfill: 5} =
               Enum.find(result.transactional, &(&1.op == :add_column))
    end

    test "carries the declared default the add's chunk leaves" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:amount, :string, []}, {:title, :string, []}]}})

      add_op = %{
        op: :add_attribute,
        entity: MyApp.Task,
        name: :priority,
        type: :integer,
        opts: [default: 5],
        line: 3
      }

      change_op = %{
        op: :change_attribute,
        entity: MyApp.Task,
        name: :priority,
        changes: [default: 7],
        line: 5
      }

      rename_op = %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4}

      same_chunk = render([add_op, change_op], pre)
      later_chunk = render([add_op, rename_op, change_op], pre)

      assert %{backfill: 7} = Enum.find(same_chunk.transactional, &(&1.op == :add_column))
      assert %{backfill: 5} = Enum.find(later_chunk.transactional, &(&1.op == :add_column))
    end

    test "keeps an explicit backfill over the declared default" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [default: 5, backfill: 0],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [%{op: :add_column, backfill: 0}] = result.transactional
    end

    # The refusal over rows reads what the member can take for its ways out: a relationship and a
    # unique attribute take no default.
    test "stamps what the member of a required add nothing fills can take" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}, MyApp.User => %{}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :code,
          type: :integer,
          opts: [optional: true],
          line: 3
        },
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :author,
          type: MyApp.User,
          opts: [optional: true],
          line: 4
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :serial,
          type: :integer,
          opts: [optional: true, unique: true],
          line: 5
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :code,
          changes: [type: :float, optional: false],
          line: 6
        },
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :author,
          changes: [optional: false],
          line: 7
        },
        # The type the attribute has already, which changes nothing.
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :serial,
          changes: [type: :integer, optional: false],
          line: 8
        }
      ]

      stamps =
        for %{op: :add_column, column: column} = op <- render(ops, pre).transactional,
            into: %{},
            do: {column, op[:unfilled]}

      assert stamps == %{
               "author_id" => %{kind: :relationship, takes_default: false, type_stated: false},
               "code" => %{kind: :attribute, takes_default: true, type_stated: true},
               "serial" => %{kind: :attribute, takes_default: false, type_stated: false}
             }
    end

    test "returns the added columns under the names the file leaves them with" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :note,
          type: :string,
          opts: [optional: true],
          line: 3
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :legacy,
          type: :integer,
          opts: [optional: true],
          line: 4
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :note, to: :remark, line: 5},
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 6},
        %{op: :delete_attribute, entity: MyApp.Job, name: :legacy, line: 7}
      ]

      result = render(ops, pre)

      assert Enum.sort_by(result.added_columns, & &1.column) == [
               %{op: :add_column, table: "my_app_job", column: "remark"},
               %{op: :add_column, table: "my_app_job", column: "remark_$search"},
               %{op: :add_column, table: "my_app_job", column: "remark_$sort"}
             ]
    end

    test "leaves an optional attribute's declared default out of its backfill" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :priority,
          type: :integer,
          opts: [optional: true, default: 5],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [add_column] = result.transactional
      refute Map.has_key?(add_column, :backfill)
    end

    test "renames an added column only on its own table" do
      pre =
        model(%{
          MyApp.Job => %{attributes: [{:title, :string, []}]},
          MyApp.Task => %{attributes: [{:title, :string, []}]}
        })

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Job,
          name: :code,
          type: :integer,
          opts: [optional: true],
          line: 3
        },
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :code,
          type: :integer,
          opts: [optional: true],
          line: 4
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :code, to: :number, line: 5}
      ]

      result = render(ops, pre)

      assert Enum.sort_by(result.added_columns, & &1.table) == [
               %{op: :add_column, table: "my_app_job", column: "code"},
               %{op: :add_column, table: "my_app_task", column: "number"}
             ]
    end

    test "leaves the columns of a table the same file drops out of the added columns" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :code,
          type: :integer,
          opts: [optional: true],
          line: 3
        },
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 4},
        %{op: :delete_entity, entity: MyApp.Job, line: 5}
      ]

      result = render(ops, pre)

      assert result.added_columns == []
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

    test "renders a deleted attribute as its column drop, the derived companions following" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:legacy, :string, []}, {:title, :string, []}]}
        })

      ops = [%{op: :delete_attribute, entity: MyApp.Task, name: :legacy, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :drop_column, table: "my_app_task", column: "legacy"},
               %{op: :drop_column, table: "my_app_task", column: "legacy_$search"},
               %{op: :drop_column, table: "my_app_task", column: "legacy_$sort"}
             ]
    end

    test "renders a deleted entity as its table drop" do
      pre = model(%{MyApp.Archive => %{}, MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :delete_entity, entity: MyApp.Archive, line: 3}]

      result = render(ops, pre)

      # The grant store follows the model: its entity_type value goes with the entity
      # type, and PostgreSQL removes an enum value only by rebuilding the type.
      assert op_kinds(result.transactional) == [:drop_table, :rebuild_enum_type]

      assert Enum.find(result.transactional, &(&1.op == :drop_table)).table == "my_app_archive"
      assert result.post_model == model(%{MyApp.Task => %{}, UserEntity => %{}})
    end

    test "renders a to-one relationship as its reference column and constraint" do
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

      # Its plain index is the index plan's, built beside the migrations.
      assert op_kinds(result.transactional) == [:add_column, :add_foreign_key]
      assert result.tail == []
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

      # Its reverse index is the index plan's, built beside the migrations.
      assert result.tail == []

      assert op_kinds(result.transactional) == [
               :create_table,
               :add_foreign_key,
               :add_foreign_key
             ]
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
          opts: [unique: true],
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

    test "builds a key's index of a table born in the file inside the transaction" do
      ops = [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :create_entity, entity: MyApp.Task, line: 4},
        %{op: :add_attribute, entity: MyApp.Task, name: :slug, type: :string, opts: [], line: 5},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :owner,
          type: MyApp.User,
          opts: [],
          line: 6
        },
        %{op: :add_unique, entity: MyApp.Task, fields: [:owner, :slug], line: 7}
      ]

      result = render(ops, Model.empty())

      assert result.tail == []

      assert %{columns: ["owner_id", "slug"], nulls_distinct: true} =
               Enum.find(
                 result.transactional,
                 &(&1.op == :create_index and &1.index == "my_app_task_owner_id_slug_$uidx")
               )

      assert result.post_model.entities[MyApp.Task].uniques == [[:owner, :slug]]
    end

    test "builds a key's index of a table that predates the file in the tail" do
      pre = model(%{MyApp.Task => %{attributes: [{:kind, :string, []}, {:slug, :string, []}]}})

      ops = [%{op: :add_unique, entity: MyApp.Task, fields: [:kind, :slug], line: 3}]

      result = render(ops, pre)

      assert result.transactional == []
      assert [create_index] = result.tail

      assert create_index.index == "my_app_task_kind_slug_$uidx"
      assert create_index.columns == ["kind", "slug"]
      assert create_index.unique == true
      assert create_index.concurrently == true
    end

    test "renders a deleted key as its index drop" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            uniques: [[:kind, :slug]]
          }
        })

      ops = [%{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug], line: 3}]

      result = render(ops, pre)

      assert result.tail == []
      assert [%{op: :drop_index, index: "my_app_task_kind_slug_$uidx"}] = result.transactional
    end

    test "renders a key whose field order changed as its index dropped and built again" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :string, []}, {:slug, :string, []}],
            uniques: [[:kind, :slug]]
          }
        })

      ops = [
        %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :slug], line: 3},
        %{op: :add_unique, entity: MyApp.Task, fields: [:slug, :kind], line: 4}
      ]

      result = render(ops, pre)

      assert [%{op: :drop_index, index: "my_app_task_kind_slug_$uidx"}] = result.transactional

      assert [
               %{
                 op: :create_index,
                 index: "my_app_task_slug_kind_$uidx",
                 columns: ["slug", "kind"]
               }
             ] =
               result.tail
    end

    test "builds a unique reference index of a table born in the file inside the transaction" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :parent,
          type: MyApp.Task,
          opts: [optional: true, unique: true],
          line: 4
        }
      ]

      result = render(ops, Model.empty())

      assert result.tail == []

      index_names =
        result.transactional
        |> Enum.filter(&(&1.op == :create_index))
        |> Enum.map(& &1.index)

      assert "my_app_task_parent_id_$uidx" in index_names
      refute "my_app_task_parent_id_$idx" in index_names
    end

    test "builds a unique reference index of a table that predates the file in the tail" do
      pre =
        model(%{
          MyApp.Task => %{relationships: [{:parent, MyApp.Task, [optional: true]}]}
        })

      ops = [
        %{
          op: :change_relationship,
          entity: MyApp.Task,
          name: :parent,
          changes: [unique: true],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert [create_index] = result.tail

      assert create_index.index == "my_app_task_parent_id_$uidx"
      assert create_index.unique == true
      assert create_index.concurrently == true
      refute Enum.any?(result.transactional, &(&1.op == :drop_index))
    end

    test "builds a unique index added before an attribute rename under the renamed names" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :handle, line: 4}
      ]

      result = render(ops, pre)

      assert [
               %{
                 op: :create_index,
                 table: "my_app_task",
                 index: "my_app_task_handle_$uidx",
                 columns: ["handle"],
                 unique: true,
                 concurrently: true
               }
             ] = result.tail

      refute Enum.any?(result.transactional, &(&1[:from] == "my_app_task_title_$uidx"))
    end

    test "builds a compound key added before a rename of one of its attributes under the renamed names" do
      pre = model(%{MyApp.Task => %{attributes: [{:kind, :string, []}, {:slug, :string, []}]}})

      ops = [
        %{op: :add_unique, entity: MyApp.Task, fields: [:kind, :slug], line: 3},
        %{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 4}
      ]

      result = render(ops, pre)

      assert [
               %{
                 op: :create_index,
                 table: "my_app_task",
                 index: "my_app_task_kind_handle_$uidx",
                 columns: ["kind", "handle"],
                 unique: true
               }
             ] = result.tail

      refute Enum.any?(result.transactional, &(&1[:from] == "my_app_task_kind_slug_$uidx"))
    end

    test "builds a unique index added before an entity rename on the renamed table" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 4}
      ]

      result = render(ops, pre)

      assert [
               %{
                 op: :create_index,
                 table: "my_app_job",
                 index: "my_app_job_title_$uidx",
                 columns: ["title"]
               }
             ] = result.tail

      refute Enum.any?(result.transactional, &(&1[:from] == "my_app_task_title_$uidx"))
    end

    # A non-unique string's sort key index is the index plan's to build and rename, not a
    # migration's (see Hologram.DB.IndexBuilder).
    test "builds no sort key index for an added attribute, under its name or the one a later rename gives it" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :note,
          type: :string,
          opts: [optional: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :note, to: :remark, line: 4}
      ]

      result = render(ops, pre)

      index_ops =
        Enum.filter(
          result.transactional ++ result.tail,
          &(&1.op in [:create_index, :drop_index, :rename_index])
        )

      assert index_ops == []
    end

    test "drops nothing and builds nothing for a unique index the same file takes back" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:amount, :string, []}, {:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4},
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: false],
          line: 5
        }
      ]

      result = render(ops, pre)

      assert result.tail == []
      refute Enum.any?(result.transactional, &(&1[:index] == "my_app_task_title_$uidx"))
    end

    test "drops nothing for a unique index the same file renames and then deletes with its attribute" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:amount, :string, []}, {:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :handle, line: 4},
        %{op: :delete_attribute, entity: MyApp.Task, name: :handle, line: 5}
      ]

      result = render(ops, pre)

      assert result.tail == []

      refute Enum.any?(
               result.transactional,
               &(&1.op in [:drop_index, :rename_index] and
                   String.ends_with?(&1[:index] || &1.from, "_$uidx"))
             )
    end

    test "builds nothing for an index on a table the same file deletes" do
      pre =
        model(%{MyApp.Task => %{attributes: [{:amount, :string, []}, {:title, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4},
        %{op: :delete_entity, entity: MyApp.Task, line: 5}
      ]

      result = render(ops, pre)

      assert result.tail == []
      assert :drop_table in op_kinds(result.transactional)
    end

    test "builds indexes of a table born in the file inside the transaction, before and after the file renames it" do
      ops = [
        %{op: :create_entity, entity: MyApp.Task, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :slug,
          type: :string,
          opts: [unique: true],
          line: 4
        },
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 5},
        %{
          op: :add_attribute,
          entity: MyApp.Job,
          name: :code,
          type: :string,
          opts: [optional: true, unique: true],
          line: 6
        }
      ]

      result = render(ops, Model.empty())

      assert result.tail == []

      assert %{table: "my_app_task"} =
               Enum.find(result.transactional, &(&1[:index] == "my_app_task_slug_$uidx"))

      assert %{op: :rename_index, to: "my_app_job_slug_$uidx"} =
               Enum.find(result.transactional, &(&1[:from] == "my_app_task_slug_$uidx"))

      assert %{table: "my_app_job"} =
               Enum.find(result.transactional, &(&1[:index] == "my_app_job_code_$uidx"))
    end

    test "builds in the tail an index on a table renamed onto the name of a table the file created and deleted" do
      pre = model(%{MyApp.Job => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{op: :create_entity, entity: MyApp.Tag, line: 3},
        %{op: :rename_attribute, entity: MyApp.Job, from: :title, to: :slug, line: 4},
        %{op: :delete_entity, entity: MyApp.Tag, line: 5},
        %{op: :rename_entity, from: MyApp.Job, to: MyApp.Tag, line: 6},
        %{op: :change_attribute, entity: MyApp.Tag, name: :slug, changes: [unique: true], line: 7}
      ]

      result = render(ops, pre)

      assert [%{op: :create_index, table: "my_app_tag", index: "my_app_tag_slug_$uidx"}] =
               result.tail
    end

    test "renames a column only in the tail builds of its own table, keeping their order" do
      pre =
        model(%{
          MyApp.Job => %{attributes: [{:title, :string, []}]},
          MyApp.Task => %{attributes: [{:amount, :string, []}, {:title, :string, []}]}
        })

      # The unrelated rename splits the file, so Task's build is emitted before Job's.
      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :title,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4},
        %{
          op: :change_attribute,
          entity: MyApp.Job,
          name: :title,
          changes: [unique: true],
          line: 5
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :handle, line: 6}
      ]

      result = render(ops, pre)

      assert [
               %{table: "my_app_task", index: "my_app_task_handle_$uidx", columns: ["handle"]},
               %{table: "my_app_job", index: "my_app_job_title_$uidx", columns: ["title"]}
             ] = result.tail
    end

    test "builds in the tail an index on a table renamed away before the file creates another under its name" do
      pre = model(%{MyApp.Task => %{attributes: [{:amount, :string, []}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :amount,
          changes: [unique: true],
          line: 3
        },
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 4},
        %{op: :create_entity, entity: MyApp.Task, line: 5}
      ]

      result = render(ops, pre)

      assert [%{op: :create_index, table: "my_app_job", index: "my_app_job_amount_$uidx"}] =
               result.tail

      refute Enum.any?(result.transactional, &(&1.op == :create_index and &1.unique))
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
                 op: :rename_enum_value,
                 enum_type: "hologram_role_grant_entity_type_$enum",
                 from: "MyApp.Draft",
                 to: "MyApp.Sketch"
               },
               %{
                 op: :rederive_grant_ids,
                 table: "hologram_role_grant",
                 column: "entity_type",
                 from: "MyApp.Draft",
                 value: "MyApp.Sketch"
               }
             ]
    end

    test "renames the derived companions with their string attribute" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "title", to: "name"},
               %{op: :rename_column, table: "my_app_task", from: "title_$sort", to: "name_$sort"},
               %{
                 op: :rename_column,
                 table: "my_app_task",
                 from: "title_$search",
                 to: "name_$search"
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
               }
             ]
    end

    test "renames a unique attribute's index with it" do
      pre = model(%{MyApp.Task => %{attributes: [{:slug, :string, [unique: true]}]}})

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}]

      result = render(ops, pre)

      assert Enum.filter(result.transactional, &(&1.op == :rename_index)) == [
               %{
                 op: :rename_index,
                 from: "my_app_task_slug_$uidx",
                 to: "my_app_task_handle_$uidx"
               }
             ]
    end

    test "renames a unique to-one relationship's index with it" do
      pre =
        model(%{
          MyApp.Task => %{relationships: [{:author, MyApp.User, [unique: true]}]},
          MyApp.User => %{}
        })

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
                 from: "my_app_task_author_id_$uidx",
                 to: "my_app_task_creator_id_$uidx"
               }
             ]
    end

    test "renames a key's index with an attribute it names" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :integer, []}, {:slug, :integer, []}],
            uniques: [[:kind, :slug]]
          }
        })

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}]

      result = render(ops, pre)

      assert result.tail == []

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "slug", to: "handle"},
               %{
                 op: :rename_index,
                 from: "my_app_task_kind_slug_$uidx",
                 to: "my_app_task_kind_handle_$uidx"
               }
             ]

      assert result.post_model.entities[MyApp.Task].uniques == [[:kind, :handle]]
    end

    test "renames a key's index with a to-one relationship it names" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:slug, :integer, []}],
            relationships: [{:owner, MyApp.User, []}],
            uniques: [[:owner, :slug]]
          },
          MyApp.User => %{}
        })

      ops = [
        %{op: :rename_relationship, entity: MyApp.Task, from: :owner, to: :author, line: 3}
      ]

      result = render(ops, pre)

      assert Enum.filter(result.transactional, &(&1.op == :rename_index)) == [
               %{
                 op: :rename_index,
                 from: "my_app_task_owner_id_slug_$uidx",
                 to: "my_app_task_author_id_slug_$uidx"
               }
             ]
    end

    test "renames the index of every key naming a renamed attribute" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :integer, []}, {:size, :integer, []}, {:slug, :integer, []}],
            uniques: [[:kind, :slug], [:slug, :size]]
          }
        })

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}]

      result = render(ops, pre)

      assert Enum.filter(result.transactional, &(&1.op == :rename_index)) == [
               %{
                 op: :rename_index,
                 from: "my_app_task_kind_slug_$uidx",
                 to: "my_app_task_kind_handle_$uidx"
               },
               %{
                 op: :rename_index,
                 from: "my_app_task_slug_size_$uidx",
                 to: "my_app_task_handle_size_$uidx"
               }
             ]
    end

    test "renders a field rename followed by a change of the key naming it, in file order" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :integer, []}, {:size, :integer, []}, {:slug, :integer, []}],
            uniques: [[:kind, :slug]]
          }
        })

      ops = [
        %{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3},
        %{op: :delete_unique, entity: MyApp.Task, fields: [:kind, :handle], line: 4},
        %{op: :add_unique, entity: MyApp.Task, fields: [:handle, :size], line: 5}
      ]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "slug", to: "handle"},
               %{
                 op: :rename_index,
                 from: "my_app_task_kind_slug_$uidx",
                 to: "my_app_task_kind_handle_$uidx"
               },
               %{op: :drop_index, index: "my_app_task_kind_handle_$uidx"}
             ]

      assert [%{op: :create_index, index: "my_app_task_handle_size_$uidx"}] = result.tail
      assert result.post_model.entities[MyApp.Task].uniques == [[:handle, :size]]
    end

    test "renames a key's index with its entity" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:kind, :integer, []}, {:slug, :integer, []}],
            uniques: [[:kind, :slug]]
          }
        })

      ops = [%{op: :rename_entity, from: MyApp.Task, to: MyApp.Chore, line: 3}]

      result = render(ops, pre)

      assert %{
               op: :rename_index,
               from: "my_app_task_kind_slug_$uidx",
               to: "my_app_chore_kind_slug_$uidx"
             } in result.transactional
    end

    test "renames a unique attribute's index with its entity" do
      pre = model(%{MyApp.Task => %{attributes: [{:slug, :string, [unique: true]}]}})

      ops = [%{op: :rename_entity, from: MyApp.Task, to: MyApp.Ticket, line: 3}]

      result = render(ops, pre)

      assert Enum.filter(result.transactional, &(&1.op == :rename_index)) == [
               %{
                 op: :rename_index,
                 from: "my_app_task_slug_$uidx",
                 to: "my_app_ticket_slug_$uidx"
               }
             ]
    end

    test "leaves another entity type's attributes of the same names alone" do
      pre =
        model(%{
          MyApp.Project => %{attributes: [{:handle, :string, []}, {:slug, :string, []}]},
          MyApp.Task => %{attributes: [{:slug, :string, []}]}
        })

      ops = [%{op: :rename_attribute, entity: MyApp.Task, from: :slug, to: :handle, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{op: :rename_column, table: "my_app_task", from: "slug", to: "handle"},
               %{
                 op: :rename_column,
                 table: "my_app_task",
                 from: "slug_$sort",
                 to: "handle_$sort"
               },
               %{
                 op: :rename_column,
                 table: "my_app_task",
                 from: "slug_$search",
                 to: "handle_$search"
               }
             ]
    end

    test "leaves another entity type's relationships of the same names alone" do
      pre =
        model(%{
          MyApp.Project => %{
            relationships: [{:author, MyApp.User, []}, {:creator, MyApp.User, []}]
          },
          MyApp.Task => %{relationships: [{:author, MyApp.User, []}]},
          MyApp.User => %{}
        })

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
               }
             ]
    end

    test "leaves another entity type's to-many relationships of the same names alone" do
      pre =
        model(%{
          MyApp.Project => %{
            relationships: [{:labels, [MyApp.Tag], []}, {:tags, [MyApp.Tag], []}]
          },
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, [MyApp.Tag], []}]}
        })

      ops = [%{op: :rename_relationship, entity: MyApp.Task, from: :tags, to: :labels, line: 3}]

      result = render(ops, pre)

      assert result.transactional == [
               %{
                 op: :rename_table,
                 from: "my_app_task_tags_$join",
                 to: "my_app_task_labels_$join"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_task_labels_$join",
                 from: "my_app_task_tags_$join_$pk",
                 to: "my_app_task_labels_$join_$pk"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_task_labels_$join",
                 from: "my_app_task_tags_$join_source_id_$fk",
                 to: "my_app_task_labels_$join_source_id_$fk"
               },
               %{
                 op: :rename_constraint,
                 table: "my_app_task_labels_$join",
                 from: "my_app_task_tags_$join_target_id_$fk",
                 to: "my_app_task_labels_$join_target_id_$fk"
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
               :rename_constraint
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
    test "renders an entity rename that moves its entity_type position as a rebuild" do
      pre = model(%{MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :rename_entity, from: UserEntity, to: MyApp.Zebra, line: 3}]

      result = render(ops, pre)

      assert Enum.find(result.transactional, &(&1.op == :rebuild_enum_type)) == %{
               op: :rebuild_enum_type,
               enum_type: "hologram_role_grant_entity_type_$enum",
               values: ["MyApp.Task", "MyApp.Zebra"],
               columns: [{"hologram_role_grant", "entity_type"}],
               remap: [
                 %{
                   from: "Hologram.Test.Fixtures.Entity.Module14",
                   to: "MyApp.Zebra",
                   scope: nil
                 }
               ]
             }

      refute Enum.any?(result.transactional, &(&1.op == :rename_enum_value))

      # The relabeled grants take the ids their new labels derive, right after the relabel.
      kinds = op_kinds(result.transactional)

      assert Enum.take(kinds, -2) == [
               :rebuild_enum_type,
               :rederive_grant_ids
             ]
    end

    test "renders an entity rename with no grant store without re-deriving grant ids" do
      pre = model(%{MyApp.Draft => %{}, MyApp.Tag => %{}})

      ops = [%{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch, line: 3}]

      result = render(ops, pre)

      refute Enum.any?(result.transactional, &(&1.op == :rederive_grant_ids))
    end

    test "renders an entity rename that keeps its entity_type position as a value rename" do
      pre = model(%{MyApp.Task => %{}, UserEntity => %{}})

      ops = [%{op: :rename_entity, from: UserEntity, to: MyApp.Account, line: 3}]

      result = render(ops, pre)

      assert Enum.find(result.transactional, &(&1.op == :rename_enum_value)) == %{
               op: :rename_enum_value,
               enum_type: "hologram_role_grant_entity_type_$enum",
               from: "Hologram.Test.Fixtures.Entity.Module14",
               to: "MyApp.Account"
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
               },
               %{
                 op: :rederive_grant_ids,
                 table: "hologram_role_grant",
                 column: "role",
                 from: "viewer",
                 value: "admin"
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
               },
               %{
                 op: :rederive_grant_ids,
                 table: "hologram_role_grant",
                 column: "role",
                 from: "moderator",
                 value: "maintainer"
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
      # whose entity_type is MyApp.Task.
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
                     scope: {"entity_type", "MyApp.Task"}
                   }
                 ]
               },
               %{
                 op: :rederive_grant_ids,
                 table: "hologram_role_grant",
                 column: "role",
                 from: "editor",
                 value: "reviewer"
               }
             ]
    end

    test "renders a global role rename as the grant store's value rename" do
      pre = %{
        entities: %{
          MyApp.Task => %{attributes: [], relationships: [], roles: [], uniques: []},
          UserEntity => %{attributes: [], relationships: [], roles: [], uniques: []}
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
               },
               %{
                 op: :rederive_grant_ids,
                 table: "hologram_role_grant",
                 column: "role",
                 from: "MyApp.Roles.Moderator",
                 value: "MyApp.Roles.Maintainer"
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
               {"my_app_sketch", "summary_$search"},
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

    test "applies a type change after the backfill of the attribute added above it" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :estimate,
          type: :float,
          opts: [backfill: 7.5],
          line: 3
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :estimate,
          changes: [type: :integer],
          line: 4
        }
      ]

      assert [add_column, alter_column] = render(ops, pre).transactional

      assert add_column.op == :add_column
      assert add_column.definition.type == "float8"
      assert add_column.backfill == 7.5

      assert alter_column.op == :alter_column
      assert alter_column.before.type == "float8"
      assert alter_column.after.type == "int8"
    end

    test "keeps a change restating the type of an attribute added with a backfill beside the add" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :seats,
          type: :integer,
          opts: [backfill: 7],
          line: 3
        },
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :owner,
          type: MyApp.Owner,
          opts: [optional: true],
          line: 4
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :seats,
          changes: [type: :integer],
          line: 5
        },
        %{op: :create_entity, entity: MyApp.Owner, line: 6}
      ]

      result = render(ops, pre)

      assert %{op: :add_column, column: "seats", backfill: 7} =
               Enum.find(result.transactional, &(&1[:column] == "seats"))

      refute Enum.any?(result.transactional, &(&1.op == :alter_column))
    end

    test "keeps a type change beside the add when the attribute added with a backfill was deleted" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :seats,
          type: :integer,
          opts: [backfill: 7],
          line: 3
        },
        %{op: :delete_attribute, entity: MyApp.Task, name: :seats, line: 4},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :seats,
          type: :integer,
          opts: [optional: true],
          line: 5
        },
        %{
          op: :add_relationship,
          entity: MyApp.Task,
          name: :owner,
          type: MyApp.Owner,
          opts: [optional: true],
          line: 6
        },
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :seats,
          changes: [type: :float],
          line: 7
        },
        %{op: :create_entity, entity: MyApp.Owner, line: 8}
      ]

      result = render(ops, pre)

      assert %{op: :add_column, column: "seats", definition: %{type: "float8"}} =
               seats = Enum.find(result.transactional, &(&1[:column] == "seats"))

      refute Map.has_key?(seats, :backfill)
      refute Enum.any?(result.transactional, &(&1.op == :alter_column))
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

    test "carries a tightening's declared default as its fill" do
      pre = model(%{MyApp.Task => %{attributes: [{:amount, :integer, [optional: true]}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :amount,
          changes: [optional: false, default: 5],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :amount, to: :cost, line: 4}
      ]

      result = render(ops, pre)

      assert %{column: "amount", fill: 5, fill_companions: []} =
               Enum.find(result.transactional, &(&1.op == :alter_column))
    end

    test "names a tightened string column's companions with its fill" do
      pre = model(%{MyApp.Task => %{attributes: [{:note, :string, [optional: true]}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :note,
          changes: [optional: false, default: "Zed"],
          line: 3
        },
        %{op: :rename_attribute, entity: MyApp.Task, from: :note, to: :remark, line: 4}
      ]

      result = render(ops, pre)

      assert %{
               column: "note",
               fill: "Zed",
               fill_companions: [sort_key: "note_$sort", search_key: "note_$search"]
             } = Enum.find(result.transactional, &(&1.op == :alter_column))
    end

    test "leaves a tightening that also changes the type without a fill" do
      pre = model(%{MyApp.Task => %{attributes: [{:amount, :string, [optional: true]}]}})

      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Task,
          name: :amount,
          changes: [type: :integer, optional: false, default: 5],
          line: 3
        }
      ]

      result = render(ops, pre)

      alter_column = Enum.find(result.transactional, &(&1.op == :alter_column))

      assert alter_column.after.null == false
      refute Map.has_key?(alter_column, :fill)
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
        %{
          op: :change_role,
          entity: MyApp.Task,
          name: :owner,
          changes: [granted_to: :creator],
          line: 4
        }
      ]

      result = render(ops, pre)

      assert result.transactional == []
      assert result.tail == []

      assert result.post_model ==
               model(%{
                 MyApp.Task => %{
                   attributes: [{:priority, :integer, [default: 0, optional: true]}],
                   roles: [{:owner, [granted_to: :creator]}]
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
          MyApp.Task => %{attributes: [], relationships: [], roles: [], uniques: []},
          UserEntity => %{attributes: [], relationships: [], roles: [], uniques: []}
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

    # The born-here exemption is the file's: Job is created before the rename, and the
    # required attribute added after it lands on Job's empty table.
    test "renders a required attribute added to an entity the same file created before a rename" do
      ops = [
        %{op: :create_entity, entity: MyApp.Job, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Job,
          name: :title,
          type: :string,
          opts: [],
          line: 4
        },
        %{op: :rename_attribute, entity: MyApp.Job, from: :title, to: :name, line: 6},
        %{op: :add_attribute, entity: MyApp.Job, name: :code, type: :integer, opts: [], line: 8}
      ]

      result = render(ops, Model.empty())

      assert %{table: "my_app_job", column: "code"} =
               Enum.find(result.transactional, &(&1.op == :add_column))

      assert result.post_model.entities[MyApp.Job].attributes == [
               {:code, :integer, []},
               {:name, :string, []}
             ]
    end

    test "refuses a required attribute added to an entity that predates the file" do
      pre = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      ops = [
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 3},
        %{op: :add_attribute, entity: MyApp.Task, name: :code, type: :integer, opts: [], line: 4}
      ]

      expected_msg =
        "required attributes added without a value for existing rows - :code on MyApp.Task - " <>
          "declare backfill: <value> for a one-time value, default: <value> to give every row " <>
          "one, or optional: true to leave them empty"

      assert_error Hologram.CompileError, expected_msg, fn -> render(ops, pre) end
    end

    # Each chunk applies on its own, so a grant delete in a later chunk would render after
    # the store's references had already moved onto the new designation.
    test "refuses a designation move whose grant delete the file puts after a rename" do
      pre =
        model(%{
          MyApp.Member => %{},
          MyApp.Task => %{attributes: [{:title, :string, []}]},
          UserEntity => %{}
        })

      ops = [
        %{op: :designate_user_entity, entity: MyApp.Member, line: 3},
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 4},
        %{op: :delete_role_grants, line: 5}
      ]

      expected_msg =
        "the user entity designation moves from #{inspect(UserEntity)} to MyApp.Member, " <>
          "and role grants reference #{inspect(UserEntity)} rows - add " <>
          "`delete_role_grants()` above it, which empties the role grant store in the " <>
          "same migration"

      assert_error Hologram.CompileError, expected_msg, fn -> render(ops, pre) end
    end

    # The same for a target deleted in one chunk and its inbound relationship in a later
    # one: the table would drop while the foreign key onto it still stands.
    test "refuses a deleted target whose inbound relationship the file deletes after a rename" do
      pre =
        model(%{
          MyApp.Task => %{
            attributes: [{:title, :string, []}],
            relationships: [{:author, MyApp.User, []}]
          },
          MyApp.User => %{}
        })

      ops = [
        %{op: :delete_entity, entity: MyApp.User, line: 3},
        %{op: :rename_attribute, entity: MyApp.Task, from: :title, to: :name, line: 4},
        %{op: :delete_relationship, entity: MyApp.Task, name: :author, line: 5}
      ]

      expected_msg =
        "relationship targets deleted at this point in migration history - " <>
          ":author on MyApp.Task targets MyApp.User - delete the relationship in the " <>
          "migration that deletes its target, or an earlier one"

      assert_error Hologram.CompileError, expected_msg, fn -> render(ops, pre) end
    end

    test "returns an empty render for ops with no physical shadow" do
      pre = model(%{MyApp.Task => %{roles: [{:editor, []}]}})

      ops = [
        %{
          op: :change_role,
          entity: MyApp.Task,
          name: :editor,
          changes: [granted_to: :creator],
          line: 3
        }
      ]

      result = render(ops, pre)

      assert result.transactional == []
      assert result.tail == []

      assert result.post_model ==
               model(%{MyApp.Task => %{roles: [{:editor, [granted_to: :creator]}]}})
    end
  end
end
