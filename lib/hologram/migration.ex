defmodule Hologram.Migration do
  @moduledoc """
  The migration vocabulary.

  A migration is a module that uses `Hologram.Migration`, compiled with the app, with
  statement-style migration ops in its body, one per line:

      defmodule MyApp.Migrations.V20260813091500 do
        @moduledoc false

        use Hologram.Migration

        change_entity MyApp.Trip do
          add_attribute :city, :string
        end
      end

  Its file lives in the app's `app/migrations/` directory and is named after its version,
  14 UTC timestamp digits like `20260813091500.ex`, and the module name ends in `V` followed
  by the same digits. The build refuses a migration module that breaks any of these.

  The module's `__hologram_migration__/0` returns the version, the file path, and the ops
  as a plain list of op maps: each flat op produces one map, and each entity block one map
  per member op. Every op map carries :op, :line, and the op's payload. Entity types are
  referenced by fully-qualified module name as spelled at that point in history - the name
  stays a valid reference after the module is renamed or deleted.

  Ops are declarations, recorded where they are written: aliases in an op resolve at that
  line, and an op inside an `if`, a comprehension or other module-body code is recorded
  regardless of it, and cannot read the module body's variables. Op arguments may call the
  module's own functions and read its attributes.

  One op declares nothing an entity type declares of itself: `designate_user_entity`
  records which entity type is the app's user, the designation `use Hologram.Entity,
  user: true` makes in the model. It rides the history like any other fact, so a replay
  knows which type the role grant store referenced at that point rather than resolving it
  against the modules as they are spelled today.

  One op changes rows rather than the model: `delete_role_grants` empties the role grant
  store. A migration whose designation moves to another entity type or is removed must
  carry it, because grants reference the designated type's rows and cannot follow the
  designation elsewhere. Requiring the line rather than deleting the grants silently keeps
  the destruction in the file, where a reviewer sees it.

  An op's options are the ones its declaration takes, with one addition: `add_attribute`
  accepts `backfill:`, the value the rows that predate the column receive. It is a
  one-time transition value rather than a declaration, so it never enters the model and
  never needs repeating in a later file - once applied, the column reads as though it had
  always been declared that way.

  A backfill must carry a value. `backfill: nil` is refused, because nil is the absence a
  backfill exists to fill. Adding a required attribute to a table that already holds rows
  needs one of these: a `backfill:`, a `default:` on the declaration, or making the
  attribute optional. Without any of them the apply refuses, naming the table and how many
  rows would have been left without a value.
  """

  alias Hologram.Migration.Loader

  # A migration module's file name is its version - 14 UTC timestamp digits, nothing else.
  @file_name_regex ~r/^\d{14}\.ex$/

  @ops_attribute :__hologram_migration_ops__

  @locals_without_parens [
    add_attribute: 2,
    add_attribute: 3,
    add_enum_value: 2,
    add_enum_value: 3,
    add_relationship: 2,
    add_relationship: 3,
    add_role: 1,
    add_role: 2,
    change_attribute: 2,
    change_relationship: 2,
    change_role: 2,
    create_entity: 1,
    delete_attribute: 1,
    delete_entity: 1,
    delete_enum_value: 2,
    delete_relationship: 1,
    delete_role: 1,
    designate_user_entity: 1,
    rename_attribute: 2,
    rename_entity: 2,
    rename_enum_value: 3,
    rename_relationship: 2,
    rename_role: 2,
    reorder_enum_values: 2,
    resolve!: 1,
    resolve!: 2
  ]

  @doc """
  Returns the vocabulary's parens-free calls, as the formatter's locals_without_parens
  option takes them - the generator formats migration files with it, and the framework
  exports the same list so a project's mix format leaves those files alone.
  """
  @spec locals_without_parens() :: keyword(pos_integer)
  def locals_without_parens, do: @locals_without_parens

  defmacro __using__(_opts) do
    imports =
      quote do
        import Hologram.Migration,
          only: [
            add_role: 1,
            add_role: 2,
            change_entity: 2,
            change_role: 2,
            create_entity: 1,
            create_entity: 2,
            delete_entity: 1,
            delete_role: 1,
            delete_role_grants: 0,
            designate_user_entity: 1,
            rename_entity: 2,
            rename_role: 2,
            resolve!: 1,
            resolve!: 2
          ]
      end

    if __CALLER__.module do
      validate_location!(__CALLER__)

      # Registered here, at expansion time, rather than in the quote below: the whole module
      # body expands before any of it runs, so the op macros store their ops before a
      # registration in the quote would run.
      Module.register_attribute(__CALLER__.module, @ops_attribute, accumulate: true)

      quote do
        unquote(imports)

        @before_compile Hologram.Migration
        @after_compile Hologram.Migration
      end
    else
      imports
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    ops =
      env.module
      |> Module.get_attribute(@ops_attribute)
      |> Enum.reverse()

    version = Path.basename(env.file, ".ex")
    path = Path.relative_to_cwd(env.file)

    quote do
      @doc false
      def __hologram_migration__ do
        %{version: unquote(version), path: unquote(path), ops: List.flatten(unquote(ops))}
      end
    end
  end

  # Runs once the module is compiled and callable, so a migration whose ops cannot be
  # evaluated, or that breaks a rule of the format, fails the build rather than the boot.
  @doc false
  @spec __after_compile__(Macro.Env.t(), binary) :: :ok
  def __after_compile__(env, _bytecode) do
    migration = env.module.__hologram_migration__()

    Loader.verify_rename_order!(migration.ops, migration.path)
  end

  @doc """
  Returns the op recording that the given global role module came into existence.

  Entity roles are declared inside entity blocks - this flat form takes a role module.
  """
  defmacro add_role(role, opts \\ []) do
    validate_global_role_args!([role], :add_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :add_role, role: unquote(role), opts: unquote(opts), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the list of member ops from the given do-block, each op recording a change
  scoped to the given existing entity type.

  Member ops are legal only inside entity blocks - the block injects its entity type
  into each of them.
  """
  defmacro change_entity(entity_type, do: block) do
    block
    |> block_statements()
    |> Enum.map(&member_op(&1, entity_type, __CALLER__))
    |> register(__CALLER__)
  end

  @doc """
  Returns the op recording that the given global role module's options changed, the
  changes as deltas.

  Entity roles change inside entity blocks - this flat form takes a role module.
  """
  defmacro change_role(role, changes) do
    validate_global_role_args!([role], :change_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :change_role, role: unquote(role), changes: unquote(changes), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the given entity type came into existence.
  """
  defmacro create_entity(entity_type) do
    line = __CALLER__.line

    op =
      quote do
        %{op: :create_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the given entity type came into existence, followed by
  the member ops from the given do-block, each scoped to it.
  """
  defmacro create_entity(entity_type, do: block) do
    line = __CALLER__.line

    create_op =
      quote do
        %{op: :create_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    member_ops =
      block
      |> block_statements()
      |> Enum.map(&member_op(&1, entity_type, __CALLER__))

    register([create_op | member_ops], __CALLER__)
  end

  @doc """
  Returns the op recording that the given entity type was deleted, its table dropped
  with its data.
  """
  defmacro delete_entity(entity_type) do
    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the given global role module was deleted, its grants
  dying with it.
  """
  defmacro delete_role(role) do
    validate_global_role_args!([role], :delete_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_role, role: unquote(role), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op deleting every grant in the role grant store.

  Required in a migration whose user entity designation moves to another entity type or
  is removed: grants reference the designated type's rows, so they cannot follow the
  designation. The deletion runs in the same transaction as the change it accompanies.
  """
  defmacro delete_role_grants do
    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_role_grants, line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the given entity type became the designated user entity
  type - the one the role grant store references and the policy layer resolves the acting
  user against. `nil` records that the designation was removed.
  """
  defmacro designate_user_entity(entity_type) do
    line = __CALLER__.line

    op =
      quote do
        %{op: :designate_user_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the first given entity type was renamed to the second,
  its table and every derived physical name following, existing data preserved.
  """
  defmacro rename_entity(old, new) do
    line = __CALLER__.line

    op =
      quote do
        %{op: :rename_entity, from: unquote(old), to: unquote(new), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the op recording that the first given global role module was renamed to the
  second, existing grants following the label.
  """
  defmacro rename_role(old, new) do
    validate_global_role_args!([old, new], :rename_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :rename_role, from: unquote(old), to: unquote(new), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Returns the placeholder op demanding human resolution of the given kind of detected
  change, with the detected facts as its payload.

  A migration file containing a resolve! op is a draft - verification, the check task,
  and the applier all refuse it until the line is replaced by the ops that express
  what happened.
  """
  defmacro resolve!(kind, payload \\ []) do
    line = __CALLER__.line

    op =
      quote do
        %{op: :resolve!, kind: unquote(kind), payload: unquote(payload), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  defp block_statements(nil), do: []

  defp block_statements({:__block__, _meta, statements}), do: statements

  defp block_statements(single_statement), do: [single_statement]

  # Aliases are expanded where the op is written: the op's code is placed in a function
  # defined at the end of the module, where an alias the module defines later would
  # otherwise change what an earlier op names. The expansion runs as though inside that
  # function, so naming an entity type is a runtime reference, as it would be written there,
  # rather than a compile-time dependency that recompiles the migration whenever the entity
  # module changes.
  defp expand_aliases(quoted, caller) do
    function_env = %{caller | function: {:__hologram_migration__, 0}}

    Macro.prewalk(quoted, fn
      {:__aliases__, _meta, _segments} = alias_ast -> Macro.expand(alias_ast, function_env)
      node -> node
    end)
  end

  # Role ops with module args are global - pattern-specific, so it must precede the
  # generic role clauses below (a module arg would otherwise build an entity-role op).
  defp member_op(
         {name, meta, [{:__aliases__, _alias_meta, _segments} | _rest]},
         _entity_type,
         caller
       )
       when name in [:add_role, :change_role, :delete_role, :rename_role] do
    raise Hologram.CompileError,
      message:
        "#{name} with a role module is a flat top-level statement - " <>
          "move it out of the entity block (line #{statement_line(meta, caller)})"
  end

  defp member_op({:add_attribute, meta, [name, type]}, entity_type, caller) do
    member_op({:add_attribute, meta, [name, type, []]}, entity_type, caller)
  end

  defp member_op({:add_attribute, meta, [name, type, opts]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        type: unquote(type),
        opts: unquote(opts),
        line: unquote(line)
      }
    end
  end

  defp member_op({:add_enum_value, meta, [attribute, value]}, entity_type, caller) do
    member_op({:add_enum_value, meta, [attribute, value, []]}, entity_type, caller)
  end

  defp member_op({:add_enum_value, meta, [attribute, value, opts]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_enum_value,
        entity: unquote(entity_type),
        attribute: unquote(attribute),
        value: unquote(value),
        opts: unquote(opts),
        line: unquote(line)
      }
    end
  end

  defp member_op({:add_relationship, meta, [name, type]}, entity_type, caller) do
    member_op({:add_relationship, meta, [name, type, []]}, entity_type, caller)
  end

  defp member_op({:add_relationship, meta, [name, type, opts]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_relationship,
        entity: unquote(entity_type),
        name: unquote(name),
        type: unquote(type),
        opts: unquote(opts),
        line: unquote(line)
      }
    end
  end

  defp member_op({:add_role, meta, [name]}, entity_type, caller) do
    member_op({:add_role, meta, [name, []]}, entity_type, caller)
  end

  defp member_op({:add_role, meta, [name, opts]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_role,
        entity: unquote(entity_type),
        name: unquote(name),
        opts: unquote(opts),
        line: unquote(line)
      }
    end
  end

  defp member_op({:change_attribute, meta, [name, changes]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :change_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        changes: unquote(changes),
        line: unquote(line)
      }
    end
  end

  defp member_op({:change_relationship, meta, [name, changes]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :change_relationship,
        entity: unquote(entity_type),
        name: unquote(name),
        changes: unquote(changes),
        line: unquote(line)
      }
    end
  end

  defp member_op({:change_role, meta, [name, changes]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :change_role,
        entity: unquote(entity_type),
        name: unquote(name),
        changes: unquote(changes),
        line: unquote(line)
      }
    end
  end

  defp member_op({:delete_attribute, meta, [name]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        line: unquote(line)
      }
    end
  end

  defp member_op({:delete_enum_value, meta, [attribute, value]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_enum_value,
        entity: unquote(entity_type),
        attribute: unquote(attribute),
        value: unquote(value),
        line: unquote(line)
      }
    end
  end

  defp member_op({:delete_relationship, meta, [name]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_relationship,
        entity: unquote(entity_type),
        name: unquote(name),
        line: unquote(line)
      }
    end
  end

  defp member_op({:delete_role, meta, [name]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_role,
        entity: unquote(entity_type),
        name: unquote(name),
        line: unquote(line)
      }
    end
  end

  defp member_op({:rename_attribute, meta, [old, new]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :rename_attribute,
        entity: unquote(entity_type),
        from: unquote(old),
        to: unquote(new),
        line: unquote(line)
      }
    end
  end

  defp member_op({:rename_enum_value, meta, [attribute, old, new]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :rename_enum_value,
        entity: unquote(entity_type),
        attribute: unquote(attribute),
        from: unquote(old),
        to: unquote(new),
        line: unquote(line)
      }
    end
  end

  defp member_op({:rename_relationship, meta, [old, new]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :rename_relationship,
        entity: unquote(entity_type),
        from: unquote(old),
        to: unquote(new),
        line: unquote(line)
      }
    end
  end

  defp member_op({:rename_role, meta, [old, new]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :rename_role,
        entity: unquote(entity_type),
        from: unquote(old),
        to: unquote(new),
        line: unquote(line)
      }
    end
  end

  defp member_op({:reorder_enum_values, meta, [attribute, values]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :reorder_enum_values,
        entity: unquote(entity_type),
        attribute: unquote(attribute),
        values: unquote(values),
        line: unquote(line)
      }
    end
  end

  defp member_op({:resolve!, meta, [kind]}, entity_type, caller) do
    member_op({:resolve!, meta, [kind, []]}, entity_type, caller)
  end

  defp member_op({:resolve!, meta, [kind, payload]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :resolve!,
        entity: unquote(entity_type),
        kind: unquote(kind),
        payload: unquote(payload),
        line: unquote(line)
      }
    end
  end

  defp member_op({name, meta, args}, _entity_type, caller) when is_atom(name) and is_list(args) do
    raise Hologram.CompileError,
      message:
        "unknown migration op #{name}/#{length(args)} at line #{statement_line(meta, caller)} - " <>
          "see Hologram.Migration for the vocabulary"
  end

  defp member_op(_statement, _entity_type, caller) do
    raise Hologram.CompileError,
      message:
        "invalid statement in a migration entity block starting at line #{caller.line} - " <>
          "entity blocks contain only member ops"
  end

  defp module_body?(caller) do
    caller.module != nil and caller.function == nil
  end

  # In a migration module's body an op is stored rather than returned - the module's
  # __hologram_migration__/0 returns the stored ops. Anywhere else the op's map is returned.
  # A module body that did not use Hologram.Migration has nowhere to store the op - a module
  # nested in a migration, or one that only imports the vocabulary - so it is refused rather
  # than dropped.
  defp register(quoted, caller) do
    cond do
      not module_body?(caller) ->
        quoted

      Module.has_attribute?(caller.module, @ops_attribute) ->
        Module.put_attribute(caller.module, @ops_attribute, expand_aliases(quoted, caller))
        nil

      true ->
        raise Hologram.CompileError,
          message:
            "#{inspect(caller.module)} holds a migration op but does not use " <>
              "Hologram.Migration (#{Path.relative_to_cwd(caller.file)}:#{caller.line})"
    end
  end

  defp statement_line(meta, caller) do
    Keyword.get(meta, :line, caller.line)
  end

  defp validate_directory!(abs_file, file) do
    dir = Path.dirname(abs_file)

    parent_dir_name =
      dir
      |> Path.dirname()
      |> Path.basename()

    if Path.basename(dir) != "migrations" or parent_dir_name != "app" do
      raise Hologram.CompileError,
        message:
          "#{file} uses Hologram.Migration - migration files live in the app/migrations/ " <>
            "directory"
    end
  end

  defp validate_file_name!(abs_file, file) do
    if not Regex.match?(@file_name_regex, Path.basename(abs_file)) do
      raise Hologram.CompileError,
        message:
          "invalid migration file name #{file} - a migration file is named after its " <>
            "version: 14 timestamp digits with the \".ex\" extension, e.g. " <>
            "\"20260813091500.ex\""
    end
  end

  # Expansion-time check: global role ops take role modules - a literal atom arg is an
  # entity-role op that belongs inside an entity block. Aliases are still AST here, so
  # the two shapes are distinguishable.
  defp validate_global_role_args!(args, op_name, caller) do
    Enum.each(args, fn arg ->
      if is_atom(arg) do
        raise Hologram.CompileError,
          message:
            "#{op_name} #{inspect(arg)} is an entity-role op - " <>
              "it lives inside a change_entity or create_entity block (line #{caller.line})"
      end
    end)
  end

  # A migration's file is named after its version, and its module after the file - the
  # version is read from the file name, and the module name only restates it, so a reader
  # never meets two versions that disagree. One directory holds every migration, so the
  # filesystem keeps versions unique.
  defp validate_location!(caller) do
    file = Path.relative_to_cwd(caller.file)

    validate_directory!(caller.file, file)
    validate_file_name!(caller.file, file)
    validate_module_name!(caller, file)
  end

  defp validate_module_name!(caller, file) do
    expected_segment = "V" <> Path.basename(caller.file, ".ex")

    # Split from the inspected name rather than with Module.split/1, which raises on a
    # module named by a bare atom - that name is refused like any other mismatch.
    module_segment =
      caller.module
      |> inspect()
      |> String.split(".")
      |> List.last()

    if module_segment != expected_segment do
      raise Hologram.CompileError,
        message:
          "#{file} defines #{inspect(caller.module)} - the module name must end in " <>
            expected_segment
    end
  end
end
