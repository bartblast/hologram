defmodule Hologram.MigrationTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration

  describe "add_role/2" do
    test "returns the op with the role module, an empty opts list by default, and the call line" do
      result = add_role(MyApp.Roles.Admin)

      assert result == %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: result.line}
      assert is_integer(result.line)
    end

    test "returns the op with the role module, the given opts, and the call line" do
      result = add_role(MyApp.Roles.Owner, extends: MyApp.Roles.Admin)

      assert result == %{
               op: :add_role,
               role: MyApp.Roles.Owner,
               opts: [extends: MyApp.Roles.Admin],
               line: result.line
             }

      assert is_integer(result.line)
    end

    test "rejects an atom arg naming an entity role" do
      code = """
      import Hologram.Migration

      add_role :moderator
      """

      expected_msg =
        "add_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 3)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "change_entity/2" do
    test "returns the member ops with the entity type injected" do
      result =
        change_entity MyApp.Task do
          add_attribute(:priority, :integer, backfill: 0)
          change_attribute(:estimate, type: :float)
          delete_attribute(:legacy)
          rename_attribute(:name, :title)
          resolve!(:attributes, deleted: [:name])
        end

      assert [add_op, change_op, delete_op, rename_op, resolve_op] = result

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

      assert rename_op == %{
               op: :rename_attribute,
               entity: MyApp.Task,
               from: :name,
               to: :title,
               line: rename_op.line
             }

      assert resolve_op == %{
               op: :resolve!,
               entity: MyApp.Task,
               kind: :attributes,
               payload: [deleted: [:name]],
               line: resolve_op.line
             }

      lines = Enum.map(result, & &1.line)
      assert length(Enum.uniq(lines)) == 5
      assert Enum.all?(lines, &is_integer/1)
    end

    test "returns enum value member ops with the entity type injected" do
      result =
        change_entity MyApp.Task do
          add_enum_value(:status, :archived, after: :done)
          delete_enum_value(:status, :draft)
          rename_enum_value(:status, :done, :completed)
          reorder_enum_values(:status, [:todo, :doing, :completed])
        end

      assert [add_op, delete_op, rename_op, reorder_op] = result

      assert add_op == %{
               op: :add_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               value: :archived,
               opts: [after: :done],
               line: add_op.line
             }

      assert delete_op == %{
               op: :delete_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               value: :draft,
               line: delete_op.line
             }

      assert rename_op == %{
               op: :rename_enum_value,
               entity: MyApp.Task,
               attribute: :status,
               from: :done,
               to: :completed,
               line: rename_op.line
             }

      assert reorder_op == %{
               op: :reorder_enum_values,
               entity: MyApp.Task,
               attribute: :status,
               values: [:todo, :doing, :completed],
               line: reorder_op.line
             }
    end

    test "returns relationship member ops with the entity type injected" do
      result =
        change_entity MyApp.Task do
          add_relationship(:author, MyApp.User)
          add_relationship(:tags, [MyApp.Tag], optional: true)
          change_relationship(:author, optional: true)
          delete_relationship(:legacy_project)
          rename_relationship(:author, :creator)
        end

      assert [add_one_op, add_many_op, change_op, delete_op, rename_op] = result

      assert add_one_op == %{
               op: :add_relationship,
               entity: MyApp.Task,
               name: :author,
               type: MyApp.User,
               opts: [],
               line: add_one_op.line
             }

      assert add_many_op == %{
               op: :add_relationship,
               entity: MyApp.Task,
               name: :tags,
               type: [MyApp.Tag],
               opts: [optional: true],
               line: add_many_op.line
             }

      assert change_op == %{
               op: :change_relationship,
               entity: MyApp.Task,
               name: :author,
               changes: [optional: true],
               line: change_op.line
             }

      assert delete_op == %{
               op: :delete_relationship,
               entity: MyApp.Task,
               name: :legacy_project,
               line: delete_op.line
             }

      assert rename_op == %{
               op: :rename_relationship,
               entity: MyApp.Task,
               from: :author,
               to: :creator,
               line: rename_op.line
             }
    end

    test "returns role member ops with the entity type injected" do
      result =
        change_entity MyApp.Task do
          add_role(:editor)
          add_role(:owner, extends: :editor)
          change_role(:owner, granted_to: :creator)
          delete_role(:viewer)
          rename_role(:moderator, :maintainer)
        end

      assert [add_op, add_extends_op, change_op, delete_op, rename_op] = result

      assert add_op == %{
               op: :add_role,
               entity: MyApp.Task,
               name: :editor,
               opts: [],
               line: add_op.line
             }

      assert add_extends_op == %{
               op: :add_role,
               entity: MyApp.Task,
               name: :owner,
               opts: [extends: :editor],
               line: add_extends_op.line
             }

      assert change_op == %{
               op: :change_role,
               entity: MyApp.Task,
               name: :owner,
               changes: [granted_to: :creator],
               line: change_op.line
             }

      assert delete_op == %{
               op: :delete_role,
               entity: MyApp.Task,
               name: :viewer,
               line: delete_op.line
             }

      assert rename_op == %{
               op: :rename_role,
               entity: MyApp.Task,
               from: :moderator,
               to: :maintainer,
               line: rename_op.line
             }
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

    test "rejects a role op with a module arg inside the block" do
      code = """
      import Hologram.Migration

      change_entity MyApp.Task do
        rename_role MyApp.Roles.Admin, MyApp.Roles.Owner
      end
      """

      expected_msg =
        "rename_role with a role module is a flat top-level statement - " <>
          "move it out of the entity block (line 4)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "change_role/2" do
    test "returns the op with the role module, the changes, and the call line" do
      result = change_role(MyApp.Roles.Owner, extends: MyApp.Roles.Admin)

      assert result == %{
               op: :change_role,
               role: MyApp.Roles.Owner,
               changes: [extends: MyApp.Roles.Admin],
               line: result.line
             }

      assert is_integer(result.line)
    end

    test "rejects an atom arg naming an entity role" do
      code = """
      import Hologram.Migration

      change_role :owner, granted_to: :creator
      """

      expected_msg =
        "change_role :owner is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 3)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "locals_without_parens/0" do
    test "is exported by the framework formatter config" do
      {config, _binding} = Code.eval_file(".formatter.exs")
      exported = get_in(config, [:export, :locals_without_parens])

      assert locals_without_parens() -- exported == []
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

  describe "delete_role/1" do
    test "returns the op with the role module and the call line" do
      result = delete_role(MyApp.Roles.Admin)

      assert result == %{op: :delete_role, role: MyApp.Roles.Admin, line: result.line}
      assert is_integer(result.line)
    end

    test "rejects an atom arg naming an entity role" do
      code = """
      import Hologram.Migration

      delete_role :moderator
      """

      expected_msg =
        "delete_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 3)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
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

  describe "rename_role/2" do
    test "returns the op with both role modules and the call line" do
      result = rename_role(MyApp.Roles.Admin, MyApp.Roles.Owner)

      assert result == %{
               op: :rename_role,
               from: MyApp.Roles.Admin,
               to: MyApp.Roles.Owner,
               line: result.line
             }

      assert is_integer(result.line)
    end

    test "rejects an atom arg naming an entity role" do
      code = """
      import Hologram.Migration

      rename_role :moderator, :maintainer
      """

      expected_msg =
        "rename_role :moderator is an entity-role op - " <>
          "it lives inside a change_entity or create_entity block (line 3)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(code)
      end
    end
  end

  describe "resolve!/2" do
    test "returns the op with the kind, an empty payload by default, and the call line" do
      result = resolve!(:attributes)

      assert result == %{op: :resolve!, kind: :attributes, payload: [], line: result.line}
      assert is_integer(result.line)
    end

    test "returns the op with the kind, the given payload, and the call line" do
      result = resolve!(:attributes, deleted: [:name], added: [:title])

      assert result == %{
               op: :resolve!,
               kind: :attributes,
               payload: [deleted: [:name], added: [:title]],
               line: result.line
             }

      assert is_integer(result.line)
    end
  end
end
