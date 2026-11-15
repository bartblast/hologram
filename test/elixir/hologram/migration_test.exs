defmodule Hologram.MigrationTest.AliasReferenceTracer do
  @moduledoc false

  # Reports to the compiling process each reference to the traced alias, with the function
  # it is made from - nil for a module-body reference, which is a compile-time dependency.
  @spec trace(tuple | atom, Macro.Env.t()) :: :ok
  def trace({:alias_reference, _meta, Hologram.MigrationTest.Traced = module}, env) do
    send(self(), {:alias_reference, module, env.function})
    :ok
  end

  def trace(_event, _env), do: :ok
end

defmodule Hologram.MigrationTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration

  alias Hologram.MigrationTest.AliasReferenceTracer

  describe "__after_compile__/2" do
    test "rejects a module referencing an entity by its pre-rename name" do
      body = """
      rename_entity MyApp.Old, MyApp.New

      change_entity MyApp.Old do
        add_attribute :title, :string
      end
      """

      expected_msg =
        "app/migrations/20260813091522.ex:7 references MyApp.Old, renamed on line 4 - " <>
          "move the rename first and use MyApp.New"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "fails the build when an op cannot be evaluated" do
      body = """
      change_entity MyApp.Task do
        add_attribute :count, :integer, default: String.to_integer("x")
      end
      """

      assert_raise ArgumentError, fn ->
        compile_migration("20260813091522", body)
      end
    end
  end

  describe "__hologram_migration__/0" do
    test "returns the version, the path and the ops of the module body, in file order" do
      module =
        compile_migration("20260813091522", """
        create_entity MyApp.Task do
          add_attribute :title, :string
        end

        delete_entity MyApp.Archive
        """)

      assert module.__hologram_migration__() == %{
               version: "20260813091522",
               path: "app/migrations/20260813091522.ex",
               ops: [
                 %{op: :create_entity, entity: MyApp.Task, line: 4},
                 %{
                   op: :add_attribute,
                   entity: MyApp.Task,
                   name: :title,
                   type: :string,
                   opts: [],
                   line: 5
                 },
                 %{op: :delete_entity, entity: MyApp.Archive, line: 8}
               ]
             }
    end

    test "returns no ops for a module without any" do
      module = compile_migration("20260813091522", "")

      assert module.__hologram_migration__().ops == []
    end

    test "keeps a regex option" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Task do
          add_attribute :code, :string, format: ~r/^[A-Z]+$/i
        end
        """)

      assert [%{opts: [format: regex]}] = module.__hologram_migration__().ops
      assert Regex.source(regex) == "^[A-Z]+$"
      assert Regex.opts(regex) == [:caseless]
    end

    test "resolves an alias where the op is written, not where the module ends" do
      module =
        compile_migration("20260813091522", """
        alias MyApp.Short

        create_entity Short

        alias MyApp.Long.Short

        delete_entity Short
        """)

      assert [first, second] = module.__hologram_migration__().ops
      assert first.entity == MyApp.Short
      assert second.entity == MyApp.Long.Short
    end

    test "returns the flat ops of every kind" do
      module =
        compile_migration("20260813091522", """
        add_role MyApp.Roles.Admin
        change_role MyApp.Roles.Admin, extends: MyApp.Roles.Member
        rename_role MyApp.Roles.Admin, MyApp.Roles.Owner
        delete_role MyApp.Roles.Guest
        designate_user_entity MyApp.User
        delete_role_grants()
        rename_entity MyApp.Old, MyApp.New
        resolve! :entities, deleted: [MyApp.Gone], added: [MyApp.Came]
        """)

      assert module.__hologram_migration__().ops == [
               %{op: :add_role, role: MyApp.Roles.Admin, opts: [], line: 4},
               %{
                 op: :change_role,
                 role: MyApp.Roles.Admin,
                 changes: [extends: MyApp.Roles.Member],
                 line: 5
               },
               %{op: :rename_role, from: MyApp.Roles.Admin, to: MyApp.Roles.Owner, line: 6},
               %{op: :delete_role, role: MyApp.Roles.Guest, line: 7},
               %{op: :designate_user_entity, entity: MyApp.User, line: 8},
               %{op: :delete_role_grants, line: 9},
               %{op: :rename_entity, from: MyApp.Old, to: MyApp.New, line: 10},
               %{
                 op: :resolve!,
                 kind: :entities,
                 payload: [deleted: [MyApp.Gone], added: [MyApp.Came]],
                 line: 11
               }
             ]
    end

    test "returns a resolve! op inside an entity block" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Task do
          resolve! :fill, attributes: [:title]
        end
        """)

      assert module.__hologram_migration__().ops == [
               %{
                 op: :resolve!,
                 entity: MyApp.Task,
                 kind: :fill,
                 payload: [attributes: [:title]],
                 line: 5
               }
             ]
    end

    test "evaluates op arguments that call the module's functions and read its attributes" do
      module =
        compile_migration("20260813091522", """
        @status_default :draft

        change_entity MyApp.Task do
          add_attribute :status, :atom, default: @status_default
          add_attribute :code, :string, default: code_default()
        end

        defp code_default, do: "A1"
        """)

      assert [%{opts: [default: :draft]}, %{opts: [default: "A1"]}] =
               module.__hologram_migration__().ops
    end

    test "returns no op written inside a function of the module" do
      module =
        compile_migration("20260813091522", """
        create_entity MyApp.Task

        def in_function, do: delete_entity(MyApp.Archive)
        """)

      assert module.__hologram_migration__().ops == [
               %{op: :create_entity, entity: MyApp.Task, line: 4}
             ]

      assert module.in_function() == %{op: :delete_entity, entity: MyApp.Archive, line: 6}
    end

    test "raises no unused alias warning for an alias used only in ops" do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          compile_migration("20260813091522", """
          alias MyApp.Task

          create_entity Task
          """)
        end)

      refute output =~ "unused alias"
    end

    test "names the entity types of its ops as runtime references, not compile-time ones" do
      previous_tracers = Code.get_compiler_option(:tracers)
      Code.put_compiler_option(:tracers, [AliasReferenceTracer | previous_tracers])

      try do
        compile_migration("20260813091522", "create_entity Hologram.MigrationTest.Traced")
      after
        Code.put_compiler_option(:tracers, previous_tracers)
      end

      assert_received {:alias_reference, Hologram.MigrationTest.Traced,
                       {:__hologram_migration__, 0}}

      refute_received {:alias_reference, Hologram.MigrationTest.Traced, nil}
    end
  end

  describe "__using__/1" do
    test "rejects a migration module outside the app/migrations directory" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "lib/my_app/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "lib/my_app/20260813091522.ex")
      end
    end

    test "rejects a migration file whose name is not a version" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "invalid migration file name app/migrations/add_tasks.ex - a migration file is named " <>
          "after its version: 14 timestamp digits with the \".ex\" extension, " <>
          "e.g. \"20260813091500.ex\""

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/add_tasks.ex")
      end
    end

    test "rejects a module whose name does not end in the version of its file" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/20260901120000.ex defines MyApp.Migrations.V20260813091522 - " <>
          "the module name must end in V20260901120000"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260901120000.ex")
      end
    end

    test "rejects an op in a module that does not use Hologram.Migration" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration

        defmodule Inner do
          create_entity MyApp.Lost
        end
      end
      """

      expected_msg =
        "MyApp.Migrations.V20260813091522.Inner holds a migration op but does not use " <>
          "Hologram.Migration (app/migrations/20260813091522.ex:5)"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.ex")
      end
    end

    test "rejects an unknown member op naming its line" do
      body = """
      change_entity MyApp.Task do
        add_column :title, :string
      end
      """

      expected_msg =
        "unknown migration op add_column/2 at line 5 - see Hologram.Migration for the vocabulary"

      assert_error Hologram.CompileError, expected_msg, fn ->
        compile_migration("20260813091522", body)
      end
    end

    test "rejects a migration file in a subdirectory of app/migrations" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/old/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/old/20260813091522.ex")
      end
    end

    test "rejects a migration file in a migrations directory outside app" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "lib/migrations/20260813091522.ex uses Hologram.Migration - " <>
          "migration files live in the app/migrations/ directory"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "lib/migrations/20260813091522.ex")
      end
    end

    test "rejects a migration file with the .exs extension" do
      code = """
      defmodule MyApp.Migrations.V20260813091522 do
        use Hologram.Migration
      end
      """

      expected_msg =
        "invalid migration file name app/migrations/20260813091522.exs - a migration file " <>
          "is named after its version: 14 timestamp digits with the \".ex\" extension, " <>
          "e.g. \"20260813091500.ex\""

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.exs")
      end
    end

    test "rejects a module named by a bare atom" do
      code = """
      defmodule :scratch_migration do
        use Hologram.Migration
      end
      """

      expected_msg =
        "app/migrations/20260813091522.ex defines :scratch_migration - " <>
          "the module name must end in V20260813091522"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.compile_string(code, "app/migrations/20260813091522.ex")
      end
    end
  end

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
