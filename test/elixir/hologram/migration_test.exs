defmodule Hologram.MigrationTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration

  describe "create_entity/1" do
    test "returns the op with the entity type and the call line" do
      result = create_entity(MyApp.Task)

      assert result == %{op: :create_entity, entity: MyApp.Task, line: result.line}
      assert is_integer(result.line)
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
