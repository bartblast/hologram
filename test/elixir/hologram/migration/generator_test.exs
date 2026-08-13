defmodule Hologram.Migration.GeneratorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Generator

  alias Hologram.Migration.Loader

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
          %{op: :change_role, entity: MyApp.Task, name: :editor, changes: [creator: true]},
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
        change_role :editor, creator: true
        rename_role :moderator, :maintainer
        delete_role :viewer
        add_enum_value :status, :doing, after: :todo
        rename_enum_value :status, :done, :completed
        delete_enum_value :status, :draft
        reorder_enum_values :status, [:todo, :doing, :completed]
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
        %{op: :add_role, role: MyApp.Roles.Support, opts: []}
      ]

      loaded =
        %{ops: ops, questions: []}
        |> render()
        |> Loader.load_string!("20260813091522.exs")

      assert Enum.map(loaded, &Map.delete(&1, :line)) == ops
    end
  end
end
