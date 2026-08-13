defmodule Hologram.Migration.RendererTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Renderer

  alias Hologram.Entity.Model

  defp model(entities) do
    entries =
      Map.new(entities, fn {entity_type, entry_overrides} ->
        entry = Map.merge(%{attributes: [], relationships: [], roles: []}, entry_overrides)

        {entity_type, entry}
      end)

    %{entities: entries, roles: %{}}
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

      assert created_tables == ["hologram_role_grant", "my_app_task"]

      task_table =
        Enum.find(result.transactional, &(&1.op == :create_table and &1.table == "my_app_task"))

      assert Map.keys(task_table.columns) == ["created_at", "id", "title", "updated_at"]
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

    test "renders a deleted attribute as its column drop" do
      pre =
        model(%{
          MyApp.Task => %{attributes: [{:legacy, :string, []}, {:title, :string, []}]}
        })

      ops = [%{op: :delete_attribute, entity: MyApp.Task, name: :legacy, line: 3}]

      result = render(ops, pre)

      assert [drop_column] = result.transactional
      assert drop_column.op == :drop_column
      assert drop_column.table == "my_app_task"
      assert drop_column.column == "legacy"
    end

    test "renders a deleted entity as its table drop" do
      pre = model(%{MyApp.Archive => %{}, MyApp.Task => %{}})

      ops = [%{op: :delete_entity, entity: MyApp.Archive, line: 3}]

      result = render(ops, pre)

      # The grant store follows the model: its resource_type value goes with the table,
      # and PostgreSQL removes an enum value only by rebuilding the type.
      assert op_kinds(result.transactional) == [:drop_table, :rebuild_enum_type]

      assert Enum.find(result.transactional, &(&1.op == :drop_table)).table == "my_app_archive"
      assert result.post_model == model(%{MyApp.Task => %{}})
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

      assert Enum.count(kinds, &(&1 == :create_table)) == 3
      assert first_reference < last_create
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
