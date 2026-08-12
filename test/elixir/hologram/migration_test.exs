defmodule Hologram.MigrationTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration

  describe "change_entity/2" do
    test "returns the member ops with the entity type injected" do
      result =
        change_entity MyApp.Task do
          add_attribute(:priority, :integer, backfill: 0)
          change_attribute(:estimate, type: :float)
          delete_attribute(:legacy)
          question(:attributes_changed, deleted: [:name])
          rename_attribute(:name, :title)
        end

      assert [add_op, change_op, delete_op, question_op, rename_op] = result

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Task,
               name: :priority,
               type: :integer,
               opts: [backfill: 0],
               line: add_op.line
             }

      assert change_op == %{
               op: :change_attribute,
               entity: MyApp.Task,
               name: :estimate,
               changes: [type: :float],
               line: change_op.line
             }

      assert delete_op == %{
               op: :delete_attribute,
               entity: MyApp.Task,
               name: :legacy,
               line: delete_op.line
             }

      assert question_op == %{
               op: :question,
               entity: MyApp.Task,
               kind: :attributes_changed,
               payload: [deleted: [:name]],
               line: question_op.line
             }

      assert rename_op == %{
               op: :rename_attribute,
               entity: MyApp.Task,
               from: :name,
               to: :title,
               line: rename_op.line
             }

      lines = Enum.map(result, & &1.line)
      assert length(Enum.uniq(lines)) == 5
      assert Enum.all?(lines, &is_integer/1)
    end

    test "returns a one-op list for a single-statement block" do
      result =
        change_entity MyApp.Task do
          add_attribute(:body, :string)
        end

      assert [add_op] = result

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Task,
               name: :body,
               type: :string,
               opts: [],
               line: add_op.line
             }
    end

    test "rejects an unknown op naming it with its line" do
      code = """
      import Hologram.Migration

      change_entity MyApp.Task do
        add_column :title, :string
      end
      """

      expected_msg =
        "unknown migration op add_column/2 at line 4 - see Hologram.Migration for the vocabulary"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end

    test "rejects a statement that is not an op call" do
      code = """
      import Hologram.Migration

      change_entity MyApp.Task do
        42
      end
      """

      expected_msg =
        "invalid statement in a migration entity block starting at line 3 - " <>
          "entity blocks contain only member ops"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "create_entity/1" do
    test "returns the op with the entity type and the call line" do
      result = create_entity(MyApp.Task)

      assert result == %{op: :create_entity, entity: MyApp.Task, line: result.line}
      assert is_integer(result.line)
    end
  end

  describe "create_entity/2" do
    test "returns the creation op followed by the member ops" do
      result =
        create_entity MyApp.Comment do
          add_attribute(:body, :string)
        end

      assert [create_op, add_op] = result
      assert create_op == %{op: :create_entity, entity: MyApp.Comment, line: create_op.line}

      assert add_op == %{
               op: :add_attribute,
               entity: MyApp.Comment,
               name: :body,
               type: :string,
               opts: [],
               line: add_op.line
             }
    end

    test "returns only the creation op for an empty block" do
      result =
        create_entity MyApp.Marker do
        end

      assert [create_op] = result
      assert create_op == %{op: :create_entity, entity: MyApp.Marker, line: create_op.line}
    end
  end

  describe "delete_entity/1" do
    test "returns the op with the entity type and the call line" do
      result = delete_entity(MyApp.Task)

      assert result == %{op: :delete_entity, entity: MyApp.Task, line: result.line}
      assert is_integer(result.line)
    end
  end

  describe "question/2" do
    test "returns the op with the kind, an empty payload by default, and the call line" do
      result = question(:rename_or_replace)

      assert result == %{op: :question, kind: :rename_or_replace, payload: [], line: result.line}
      assert is_integer(result.line)
    end

    test "returns the op with the kind, the given payload, and the call line" do
      result = question(:attributes_changed, deleted: [:name], added: [:title])

      assert result == %{
               op: :question,
               kind: :attributes_changed,
               payload: [deleted: [:name], added: [:title]],
               line: result.line
             }

      assert is_integer(result.line)
    end
  end

  describe "rename_entity/2" do
    test "returns the op with both entity type names and the call line" do
      result = rename_entity(MyApp.Draft, MyApp.Sketch)

      assert result == %{
               op: :rename_entity,
               from: MyApp.Draft,
               to: MyApp.Sketch,
               line: result.line
             }

      assert is_integer(result.line)
    end
  end
end
