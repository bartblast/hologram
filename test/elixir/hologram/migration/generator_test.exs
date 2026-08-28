defmodule Hologram.Migration.GeneratorTest do
  # async: false - resolve!-free generate outcomes shadow-verify against the scratch
  # database, a per-suite singleton (the configured name + "_shadow").
  use Hologram.Test.BasicCase, async: false

  import Hologram.Migration.Generator

  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader
  alias Hologram.Reflection

  @tmp_dir Path.join([Reflection.tmp_dir(), "tests", "migration", "generator"])

  @timestamp ~U[2026-08-13 09:15:22Z]

  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry = Map.merge(%{attributes: [], relationships: [], roles: []}, entry_overrides)

        {entity_type, entry}
      end)

    %{entities: entries, roles: %{}, user_entity: nil}
  end

  defp migrations_dir!(test_dir, files \\ []) do
    dir = Path.join(@tmp_dir, test_dir)

    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    Enum.each(files, fn {file_name, contents} ->
      dir
      |> Path.join(file_name)
      |> File.write!(contents)
    end)

    dir
  end

  describe "generate/3" do
    test "writes the migration taking the history to the model" do
      dir = migrations_dir!("writes_migration")
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 0} = generate(dir, current, @timestamp)
      assert path == Path.join(dir, "20260813091522.exs")

      expected =
        normalize_newlines("""
        use Hologram.Migration

        create_entity MyApp.Task do
          add_attribute :title, :string
        end
        """)

      assert File.read!(path) == expected
    end

    test "returns the question count of a generated draft" do
      contents = """
      use Hologram.Migration

      create_entity MyApp.Task do
        add_attribute :name, :string
      end
      """

      dir = migrations_dir!("draft_count", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:ok, path, 1} = generate(dir, current, @timestamp)

      assert path
             |> File.read!()
             |> String.contains?("resolve! :attributes")
    end

    test "does nothing when the history already produces the model" do
      contents = """
      use Hologram.Migration

      create_entity MyApp.Task do
        add_attribute :title, :string
      end
      """

      dir = migrations_dir!("nothing_to_do", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert generate(dir, current, @timestamp) == :nothing_to_do
      assert File.ls!(dir) == ["20260813091522.exs"]
    end

    test "writes an option's regex with the modifiers it was declared with" do
      dir = migrations_dir!("regex_option")

      current =
        model(%{
          MyApp.Task => %{attributes: [{:title, :string, [format: {:regex, "^a", [:caseless]}]}]}
        })

      assert {:ok, path, 0} = generate(dir, current, @timestamp)

      expected =
        normalize_newlines("""
        use Hologram.Migration

        create_entity MyApp.Task do
          add_attribute :title, :string, format: ~r/^a/i
        end
        """)

      assert File.read!(path) == expected
    end

    test "the history it writes for a model holding a regex produces that model" do
      dir = migrations_dir!("regex_round_trip")

      current =
        model(%{MyApp.Task => %{attributes: [{:title, :string, [format: {:regex, "^a", []}]}]}})

      assert {:ok, _path, 0} = generate(dir, current, @timestamp)

      replayed =
        dir
        |> Loader.load_dir!()
        |> Enum.reduce(Model.empty(), &Model.fold(&2, &1.ops))

      assert replayed == current
    end

    test "bumps the version while the minted name is taken" do
      dir = migrations_dir!("bumps_version", [{"20260813091522.exs", "use Hologram.Migration\n"}])
      current = model(%{MyApp.Task => %{}})

      assert {:ok, path, 0} = generate(dir, current, @timestamp)
      assert path == Path.join(dir, "20260813091523.exs")
    end

    test "refuses to generate while a draft holds unanswered questions" do
      contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        resolve! :attributes, deleted: [:name], added: [:title]
      end
      """

      dir = migrations_dir!("unresolved", [{"20260813091522.exs", contents}])
      current = model(%{MyApp.Task => %{attributes: [{:title, :string, []}]}})

      assert {:error, {:unresolved, [{path, op}]}} = generate(dir, current, @timestamp)
      assert path == Path.join(dir, "20260813091522.exs")
      assert op.kind == :attributes
      assert op.line == 4
      assert File.ls!(dir) == ["20260813091522.exs"]
    end

    test "refuses a resolved history that cannot build the model's schema" do
      create_contents = """
      use Hologram.Migration

      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      narrow_contents = """
      use Hologram.Migration

      change_entity MyApp.Task do
        change_relationship :tags, type: MyApp.Tag
      end
      """

      dir =
        migrations_dir!("narrowing", [
          {"20260813091522.exs", create_contents},
          {"20260813091523.exs", narrow_contents}
        ])

      current =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}
        })

      expected_msg =
        "changing relationship :tags on MyApp.Task from to-many to to-one is not " <>
          "supported - a row holding several targets has no one target to keep - " <>
          "delete the relationship and add it with the new cardinality, or write " <>
          "the migration that picks the survivors"

      assert_error Hologram.CompileError, expected_msg, fn ->
        generate(dir, current, @timestamp)
      end
    end

    test "leaves no file behind when the written migration fails verification" do
      create_contents = """
      use Hologram.Migration

      create_entity MyApp.Tag

      create_entity MyApp.Task do
        add_relationship :tags, [MyApp.Tag]
      end
      """

      dir = migrations_dir!("unverifiable", [{"20260813091522.exs", create_contents}])

      current =
        model(%{
          MyApp.Tag => %{},
          MyApp.Task => %{relationships: [{:tags, MyApp.Tag, []}]}
        })

      assert_raise Hologram.CompileError, fn -> generate(dir, current, @timestamp) end

      # The rejected file would otherwise become the next run's history, which replays the
      # ops that failed and reports the same error with nothing naming the cause.
      assert File.ls!(dir) == ["20260813091522.exs"]
    end
  end

  describe "render/1" do
    test "renders entity blocks in alphabetical order after the renames" do
      plan = %{
        ops: [
          %{op: :create_entity, entity: MyApp.Comment},
          %{op: :add_attribute, entity: MyApp.Comment, name: :body, type: :string, opts: []},
          %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch},
          %{op: :rename_attribute, entity: MyApp.Task, from: :name, to: :title},
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [optional: true]
          },
          %{op: :delete_entity, entity: MyApp.Archive}
        ],
        questions: []
      }

      expected = """
      use Hologram.Migration

      rename_entity MyApp.Draft, MyApp.Sketch

      create_entity MyApp.Comment do
        add_attribute :body, :string
      end

      change_entity MyApp.Task do
        rename_attribute :name, :title
        add_attribute :priority, :integer, optional: true
      end

      delete_entity MyApp.Archive
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders the user entity designation after the entity blocks" do
      plan = %{
        ops: [
          %{op: :create_entity, entity: MyApp.Account},
          %{op: :add_attribute, entity: MyApp.Account, name: :email, type: :string, opts: []},
          %{op: :designate_user_entity, entity: MyApp.Account}
        ],
        questions: []
      }

      expected = """
      use Hologram.Migration

      create_entity MyApp.Account do
        add_attribute :email, :string
      end

      designate_user_entity MyApp.Account
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders the role grant deletion, the one op carrying parens" do
      plan = %{ops: [%{op: :delete_role_grants}], questions: []}

      expected = """
      use Hologram.Migration

      delete_role_grants()
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders a removed user entity designation as nil" do
      plan = %{ops: [%{op: :designate_user_entity, entity: nil}], questions: []}

      expected = """
      use Hologram.Migration

      designate_user_entity nil
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders a moved designation question with both ops the answer needs" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :user_entity,
            from: MyApp.User,
            to: MyApp.Account,
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      # RESOLVE: the user entity designation is moving from MyApp.User to MyApp.Account - role grants reference MyApp.User rows, so they cannot follow it.
      # Write both ops, then delete the resolve! line. API:
      #   delete_role_grants()                   - every grant in the store is deleted
      #   designate_user_entity MyApp.Account    - the store's references follow it
      resolve! :user_entity, from: MyApp.User, to: MyApp.Account
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders a removed designation question as the store's drop" do
      plan = %{
        ops: [],
        questions: [%{kind: :user_entity, from: MyApp.User, to: nil, withheld_ops: []}]
      }

      rendered = render(plan)

      assert rendered =~
               "designate_user_entity nil              - the role grant store is dropped"

      assert rendered =~ "resolve! :user_entity, from: MyApp.User, to: nil"
    end

    test "renders a fill question with the op spelled out three ways" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :fill,
            entity: MyApp.Task,
            attributes: [:title],
            members: [{:title, :string, []}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      change_entity MyApp.Task do
        # RESOLVE: :title is required, and MyApp.Task already holds rows - they need a value.
        # Write the op with one of these, then delete the resolve! line. API:
        #   add_attribute :title, :string, backfill: <value>  - existing rows receive it, once
        #   add_attribute :title, :string, default: <value>   - every row created without one, from now on
        #   add_attribute :title, :string, optional: true     - existing rows stay empty
        resolve! :fill, attributes: [:title]
      end
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders every entity-scoped op kind" do
      plan = %{
        ops: [
          %{
            op: :change_attribute,
            entity: MyApp.Task,
            name: :estimate,
            changes: [default: nil, type: :float]
          },
          %{op: :delete_attribute, entity: MyApp.Task, name: :legacy},
          %{
            op: :add_relationship,
            entity: MyApp.Task,
            name: :tags,
            type: [MyApp.Tag],
            opts: [optional: true]
          },
          %{
            op: :change_relationship,
            entity: MyApp.Task,
            name: :author,
            changes: [type: MyApp.Account]
          },
          %{op: :rename_relationship, entity: MyApp.Task, from: :author, to: :creator},
          %{op: :delete_relationship, entity: MyApp.Task, name: :project},
          %{op: :add_role, entity: MyApp.Task, name: :owner, opts: [extends: :editor]},
          %{op: :change_role, entity: MyApp.Task, name: :editor, changes: [granted_to: :creator]},
          %{op: :rename_role, entity: MyApp.Task, from: :moderator, to: :maintainer},
          %{op: :delete_role, entity: MyApp.Task, name: :viewer},
          %{
            op: :add_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            value: :doing,
            opts: [after: :todo]
          },
          %{
            op: :rename_enum_value,
            entity: MyApp.Task,
            attribute: :status,
            from: :done,
            to: :completed
          },
          %{op: :delete_enum_value, entity: MyApp.Task, attribute: :status, value: :draft},
          %{
            op: :reorder_enum_values,
            entity: MyApp.Task,
            attribute: :status,
            values: [:todo, :doing, :completed]
          }
        ],
        questions: []
      }

      expected = """
      use Hologram.Migration

      change_entity MyApp.Task do
        change_attribute :estimate, default: nil, type: :float
        delete_attribute :legacy
        add_relationship :tags, [MyApp.Tag], optional: true
        change_relationship :author, type: MyApp.Account
        rename_relationship :author, :creator
        delete_relationship :project
        add_role :owner, extends: :editor
        change_role :editor, granted_to: :creator
        rename_role :moderator, :maintainer
        delete_role :viewer
        add_enum_value :status, :doing, after: :todo
        rename_enum_value :status, :done, :completed
        delete_enum_value :status, :draft
        # The declared order of :status changed - queries ordering by it sort rows differently now.
        # No value changes: every row keeps what it holds, and the column is rebuilt to apply the order.
        reorder_enum_values :status, [:todo, :doing, :completed]
      end
      """

      assert render(plan) == normalize_newlines(expected)
    end

    # A reorder reads as a refactor and is not one - the declared order is what ordering by the
    # attribute follows - so the draft says what changed, and what did not.
    test "warns above a reorder, saying no value changes" do
      plan = %{
        ops: [
          %{
            op: :reorder_enum_values,
            entity: MyApp.Task,
            attribute: :priority,
            values: [:high, :low, :medium]
          }
        ],
        questions: []
      }

      expected = """
      use Hologram.Migration

      change_entity MyApp.Task do
        # The declared order of :priority changed - queries ordering by it sort rows differently now.
        # No value changes: every row keeps what it holds, and the column is rebuilt to apply the order.
        reorder_enum_values :priority, [:high, :low, :medium]
      end
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders global role ops as flat statements" do
      plan = %{
        ops: [
          %{op: :add_role, role: MyApp.Roles.Support, opts: [extends: [MyApp.Roles.Admin]]},
          %{op: :change_role, role: MyApp.Roles.Owner, changes: [extends: nil]},
          %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Manager},
          %{op: :delete_role, role: MyApp.Roles.Legacy}
        ],
        questions: []
      }

      expected = """
      use Hologram.Migration

      add_role MyApp.Roles.Support, extends: [MyApp.Roles.Admin]

      change_role MyApp.Roles.Owner, extends: nil

      rename_role MyApp.Roles.Admin, MyApp.Roles.Manager

      delete_role MyApp.Roles.Legacy
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders an entity-scoped question inside its block, before the ops" do
      plan = %{
        ops: [
          %{
            op: :add_attribute,
            entity: MyApp.Task,
            name: :priority,
            type: :integer,
            opts: [backfill: 0]
          }
        ],
        questions: [
          %{
            kind: :attributes,
            entity: MyApp.Task,
            deleted: [:desc, :name],
            added: [:body, :title],
            hints: [{:rename, :name, :title}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      change_entity MyApp.Task do
        # RESOLVE: :desc, :name disappeared from the attributes - :body, :title appeared.
        # Write the ops that express what happened, then delete the resolve! line. API:
        #   rename_attribute :old, :new             - the column is renamed, its data kept
        #   delete_attribute :name                  - the column and its data are dropped
        #   add_attribute :name, :type, opts        - a new column, empty for existing rows
        # Looks likely: rename_attribute :name, :title
        resolve! :attributes, deleted: [:desc, :name], added: [:body, :title]
        add_attribute :priority, :integer, backfill: 0
      end
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders an entity question at the top level" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :entities,
            deleted: [MyApp.Draft],
            added: [MyApp.Sketch],
            hints: [{:rename, MyApp.Draft, MyApp.Sketch}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      # RESOLVE: MyApp.Draft disappeared from the entity types - MyApp.Sketch appeared.
      # Write the ops that express what happened, then delete the resolve! line. API:
      #   rename_entity MyApp.Old, MyApp.New      - the table is renamed, its rows kept
      #   delete_entity MyApp.Old                 - the table and its rows are dropped
      #   create_entity MyApp.New do ... end      - a new table
      # Looks likely: rename_entity MyApp.Draft, MyApp.Sketch
      resolve! :entities, deleted: [MyApp.Draft], added: [MyApp.Sketch]
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "names the attribute in an enum value question" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :enum_values,
            entity: MyApp.Task,
            attribute: :status,
            deleted: [:done],
            added: [:completed],
            hints: [{:rename, :done, :completed}],
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      change_entity MyApp.Task do
        # RESOLVE: :done disappeared from the values of :status - :completed appeared.
        # Write the ops that express what happened, then delete the resolve! line. API:
        #   rename_enum_value :attr, :old, :new     - the rows holding it follow the label
        #   delete_enum_value :attr, :value         - refused while rows still hold it
        #   add_enum_value :attr, :value, opts      - before:/after: place it in the order
        # Looks likely: rename_enum_value :status, :done, :completed
        resolve! :enum_values, attribute: :status, deleted: [:done], added: [:completed]
      end
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders a question without hints" do
      plan = %{
        ops: [],
        questions: [
          %{
            kind: :roles,
            deleted: [MyApp.Roles.Moderator, MyApp.Roles.Legacy],
            added: [MyApp.Roles.Maintainer],
            hints: [],
            withheld_ops: []
          }
        ]
      }

      expected = """
      use Hologram.Migration

      # RESOLVE: MyApp.Roles.Moderator, MyApp.Roles.Legacy disappeared from the roles - MyApp.Roles.Maintainer appeared.
      # Write the ops that express what happened, then delete the resolve! line. API:
      #   rename_role :old, :new                  - existing grants follow the label
      #   delete_role :name                       - the grants of that role die with it
      #   add_role :name, opts                    - a new grantable role
      resolve! :roles,
        deleted: [MyApp.Roles.Moderator, MyApp.Roles.Legacy],
        added: [MyApp.Roles.Maintainer]
      """

      assert render(plan) == normalize_newlines(expected)
    end

    test "renders text the loader reads back as the given ops" do
      ops = [
        %{op: :rename_entity, from: MyApp.Draft, to: MyApp.Sketch},
        %{op: :create_entity, entity: MyApp.Comment},
        %{op: :add_attribute, entity: MyApp.Comment, name: :body, type: :string, opts: []},
        %{
          op: :add_enum_value,
          entity: MyApp.Task,
          attribute: :status,
          value: :doing,
          opts: [after: :todo]
        },
        %{op: :add_role, role: MyApp.Roles.Support, opts: []},
        %{op: :change_role, role: MyApp.Roles.Support, changes: [extends: [MyApp.Roles.Staff]]},
        %{op: :delete_role_grants},
        %{op: :designate_user_entity, entity: MyApp.Comment}
      ]

      loaded =
        %{ops: ops, questions: []}
        |> render()
        |> Loader.load_string!("20260813091522.exs")

      assert Enum.map(loaded, &Map.delete(&1, :line)) == ops
    end

    test "renders a draft the loader reads back with its resolve! op" do
      question = %{
        kind: :attributes,
        entity: MyApp.Task,
        deleted: [:name],
        added: [:title],
        hints: [{:rename, :name, :title}],
        withheld_ops: []
      }

      loaded =
        %{ops: [], questions: [question]}
        |> render()
        |> Loader.load_string!("20260813091522.exs")

      assert Enum.map(loaded, &Map.delete(&1, :line)) == [
               %{
                 op: :resolve!,
                 entity: MyApp.Task,
                 kind: :attributes,
                 payload: [deleted: [:name], added: [:title]]
               }
             ]

      assert Loader.unresolved(loaded) == loaded
    end
  end
end
