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
  module's own functions and read its attributes, an attribute read giving the value it holds
  at the op's line. In `backfill:` such a call or read is pinned, like `^my_fun()` or `^@x`,
  since a bare name there is a field of the row.

  A migration's functions and ops may call only its own functions and the standard
  library's functions that compute on the values they are given - most of Kernel, String,
  Enum, Map, Date and their like - so what it does to rows never changes once it is
  applied. The build refuses a call to any other function, the app's and those reading the
  clock, the environment, a random source or the time zone database among them, and a call
  to a module chosen at runtime, like `apply/3` or `mod.fun()`. Field access on a value,
  like `row.name`, reads only a map or struct: given a module, it raises rather than calling
  the module's function. The module body, which runs once per build, is checked by the
  modules it uses: the build refuses one outside the standard libraries, and the standard
  ones that read the environment, like System, File and Application.

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

  An op's options are the ones its declaration takes, with one addition: `backfill:`, what
  the rows that predate the change receive. `add_attribute` and `add_relationship` (to-one)
  take it, and so do `change_attribute` and `change_relationship` (to-one) turning an
  optional member required with no type change, which fill only the rows holding nil. It is
  a one-time transition value rather than a declaration, so it never enters the model and
  never needs repeating in a later file - once applied, the column reads as though it had
  always been declared that way.

  A backfill is a constant, or an expression computed from each row:

      add_attribute :tier, :string, backfill: "standard"
      add_attribute :tier, :string, backfill: ^@default_tier
      add_attribute :city, :string, backfill: destination |> split(", ") |> at(0)
      add_attribute :title, :string, backfill: "Trip to " <> destination
      add_attribute :name, :string, backfill: coalesce(nickname, first_name <> " " <> last_name)
      add_attribute :tag_count, :integer, backfill: count(tags)
      add_attribute :main_tag, :string, backfill: tags |> most_common(name)
      add_attribute :currency, :string, backfill: trip.currency

  A bare name is a field of the row, and a dot chain reads through to-one relationships,
  giving nil when a reference is nil. Anything from the surrounding Elixir code is pinned
  with `^`, an attribute or a sigil included. The words are:

    * `a <> b` joins strings, giving nil when any of them is nil
    * `split(text, separator)` splits as `String.split/2`, giving nil for nil, and is read
      through `at`, since a list can't be stored
    * `at(split(...), n)` picks a part as `Enum.at/2`, counting from 0, giving nil past the end
    * `coalesce(a, b, ...)` gives the first value that isn't nil
    * `count(set)` counts the rows of a to-many relationship, giving 0 for none
    * `most_common(set, attribute)` gives the attribute's most frequent value among the
      set's rows, skipping nil, a tie going to the smallest in `sort` order, and nil when no
      row holds a value

  A `fn` names the row's fields and relationships it reads as its arguments. Its body is a query
  when its outermost part is one of these words, when it's only a field or a path, or when it's
  wrapped in `query(...)`, and then it runs as one `UPDATE`:

      add_attribute :city, :string, backfill: fn destination ->
        destination |> split(", ") |> at(0)
      end
      add_attribute :label, :string, backfill: fn title, city ->
        query(title <> " in " <> city)
      end
      add_attribute :stop_count, :integer, backfill: fn id ->
        Offgrid.Stop |> filter(trip_id == ^id) |> count()
      end
      add_attribute :currency, :string, backfill: fn id ->
        Offgrid.Stop |> filter(trip_id == ^id) |> most_common(currency)
      end

  Inside a query, a module attribute is pinned (`^@x`). A call to a function the file imports or
  the module defines is that function rather than a word of the same name, except inside
  `query(...)`, which a module can't define as `query/1` beside a body using it.

  Any other body is Elixir, and runs row by row:

      add_attribute :slug, :string, backfill: fn title ->
        title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
      end

  Its arguments are the row's own fields, and the body is pure: the standard library's value
  functions and the migration's own functions. A module attribute is plain `@x` there, read where
  the op is written. It can't call a query word, so an operator beside one, like
  `coalesce(a, b) <> "!"`, needs `query(...)` around the whole body.

  Where this departs from an entity's derived field: a query reaches the rows pointing at this one
  by `Type |> filter(<ref>_id == ^id)`, since a migration's history records no declared inverse,
  and it takes only the words above, with no `if` and no comparison outside that filter.

  A to-one relationship takes the id of a row of its target, as a constant or an expression:

      add_relationship :owner, Offgrid.User, backfill: ^@admin_id
      add_relationship :owner, Offgrid.User, backfill: coalesce(creator_id, ^@admin_id)
      add_relationship :owner, Offgrid.User, backfill: trip.owner_id

  An id no row of the target holds is refused, naming the id and the type. Adding a required
  to-one to a type that already exists needs a `backfill:` or `optional: true`, since a
  relationship takes no `default:`.

  Every backfill reads the rows as the ops above it left them, so deleting a field it reads
  goes below it. Types are strict: the expression's type must be the member's. A required
  member an expression leaves nil refuses with the count of rows, the filled values are
  checked against the member's declared rules, and a `default:` never fills what a backfill
  left nil. A fill leaves `updated_at`, `server_updated_at` and the rows' revisions alone.

  A backfill must carry a value. `backfill: nil` is refused, because nil is the absence a
  backfill exists to fill. Adding a required attribute to a table that already holds rows
  needs one of these: a `backfill:`, a `default:` on the declaration, or making the
  attribute optional. Without any of them the apply refuses, naming the table and how many
  rows would have been left without a value.

  A key declared with `unique` is a member of its entity type like any other: `add_unique`
  and `delete_unique` take the key's fields in declared order. A key follows a rename of a
  field it names, and stands in the way of deleting one - the file deletes the key first.
  """

  alias Hologram.Migration.CallCheck
  alias Hologram.Migration.FieldAccess
  alias Hologram.Migration.Loader
  alias Hologram.Migration.Value

  # A migration module's file name is its version - 14 UTC timestamp digits, nothing else.
  @file_name_regex ~r/^\d{14}\.ex$/

  @ops_attribute :__hologram_migration_ops__

  @snapshots_attribute :__hologram_migration_snapshots__

  @fn_backfills_attribute :__hologram_migration_fn_backfills__

  @op_imports_attribute :__hologram_migration_op_imports__

  @locals_without_parens [
    add_attribute: 2,
    add_attribute: 3,
    add_enum_value: 2,
    add_enum_value: 3,
    add_relationship: 2,
    add_relationship: 3,
    add_role: 1,
    add_role: 2,
    add_unique: 1,
    change_attribute: 2,
    change_relationship: 2,
    change_role: 2,
    create_entity: 1,
    delete_attribute: 1,
    delete_entity: 1,
    delete_enum_value: 2,
    delete_relationship: 1,
    delete_role: 1,
    delete_unique: 1,
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
  option takes them - the generator's default formatting uses it, and the framework
  exports the same list so a project importing Hologram's formatter config writes migration
  files parens-free too.
  """
  @spec locals_without_parens() :: keyword(pos_integer)
  def locals_without_parens, do: @locals_without_parens

  defmacro __using__(_opts) do
    if __CALLER__.module == nil do
      raise Hologram.CompileError,
        message:
          "use Hologram.Migration goes in a migration module - " <>
            "#{Path.relative_to_cwd(__CALLER__.file)}:#{__CALLER__.line}"
    end

    validate_location!(__CALLER__)

    # Registered here, at expansion time, rather than in the quote below: the whole module
    # body expands before any of it runs, so the op macros store their ops before a
    # registration in the quote would run.
    Module.register_attribute(__CALLER__.module, @ops_attribute, accumulate: true)
    Module.register_attribute(__CALLER__.module, @snapshots_attribute, accumulate: true)
    Module.register_attribute(__CALLER__.module, @fn_backfills_attribute, accumulate: true)
    Module.register_attribute(__CALLER__.module, @op_imports_attribute, accumulate: true)

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

      # Field access on a value compiles into a strict map read (see
      # Hologram.Migration.FieldAccess.Definitions).
      import Kernel,
        except: [
          def: 1,
          def: 2,
          defguard: 1,
          defguardp: 1,
          defmacro: 1,
          defmacro: 2,
          defmacrop: 1,
          defmacrop: 2,
          defp: 1,
          defp: 2
        ]

      import Hologram.Migration.FieldAccess.Definitions,
        only: [
          def: 1,
          def: 2,
          defguard: 1,
          defguardp: 1,
          defmacro: 1,
          defmacro: 2,
          defmacrop: 1,
          defmacrop: 2,
          defp: 1,
          defp: 2
        ]

      # The call check reads the module's debug info - kept for migration modules even where
      # the project compiles without it, as a test run does.
      @compile {:debug_info, true}

      @before_compile Hologram.Migration
      @after_compile Hologram.Migration
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    validate_snapshots_taken!(env)
    validate_op_imports!(env)

    {settled_ops, functions} =
      env.module
      |> Module.get_attribute(@ops_attribute)
      |> Enum.reverse()
      |> settle_fn_backfills(env)

    ops = FieldAccess.rewrite(settled_ops)

    version = Path.basename(env.file, ".ex")
    path = Path.relative_to_cwd(env.file)

    quote do
      unquote_splicing(functions)

      @doc false
      def __hologram_migration__ do
        %{version: unquote(version), path: unquote(path), ops: List.flatten(unquote(ops))}
      end
    end
  end

  # Runs once the module is compiled and callable, so a migration whose ops cannot be
  # evaluated, or that breaks a rule of the format, fails the build rather than the boot.
  # The calls are checked first: evaluating the ops runs the code they call.
  @doc false
  @spec __after_compile__(Macro.Env.t(), binary) :: :ok
  def __after_compile__(env, bytecode) do
    CallCheck.validate!(env, bytecode)

    migration = env.module.__hologram_migration__()

    Value.validate_ops!(migration.ops, migration.path, env.module)
    Loader.verify_rename_order!(migration.ops, migration.path)
    Loader.validate_resolved!([migration], build_env())
  end

  @doc """
  Records that the given global role module came into existence.

  Entity roles are declared inside entity blocks - this flat form takes a role module.
  """
  defmacro add_role(role, opts \\ []) do
    validate_placement!(__CALLER__)
    validate_global_role_args!([role], :add_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :add_role, role: unquote(role), opts: unquote(opts), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records the member ops of the given do-block, each op recording a change scoped to
  the given existing entity type.

  Member ops are legal only inside entity blocks - the block injects its entity type
  into each of them.
  """
  defmacro change_entity(entity_type, do: block) do
    validate_placement!(__CALLER__)

    block
    |> block_statements()
    |> Enum.map(&member_op(&1, entity_type, __CALLER__))
    |> register(__CALLER__)
  end

  @doc """
  Records that the given global role module's options changed, the changes as deltas.

  Entity roles change inside entity blocks - this flat form takes a role module.
  """
  defmacro change_role(role, changes) do
    validate_placement!(__CALLER__)
    validate_global_role_args!([role], :change_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :change_role, role: unquote(role), changes: unquote(changes), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the given entity type came into existence.
  """
  defmacro create_entity(entity_type) do
    validate_placement!(__CALLER__)

    line = __CALLER__.line

    op =
      quote do
        %{op: :create_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the given entity type came into existence, followed by the member ops of
  the given do-block, each scoped to it.
  """
  defmacro create_entity(entity_type, do: block) do
    validate_placement!(__CALLER__)

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
  Records that the given entity type was deleted, its table dropped with its data.
  """
  defmacro delete_entity(entity_type) do
    validate_placement!(__CALLER__)

    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the given global role module was deleted, its grants dying with it.
  """
  defmacro delete_role(role) do
    validate_placement!(__CALLER__)
    validate_global_role_args!([role], :delete_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_role, role: unquote(role), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records the op deleting every grant in the role grant store.

  Required in a migration whose user entity designation moves to another entity type or
  is removed: grants reference the designated type's rows, so they cannot follow the
  designation. The deletion runs in the same transaction as the change it accompanies.
  """
  defmacro delete_role_grants do
    validate_placement!(__CALLER__)

    line = __CALLER__.line

    op =
      quote do
        %{op: :delete_role_grants, line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the given entity type became the designated user entity type - the one
  the role grant store references and the policy layer resolves the acting user against.
  `nil` records that the designation was removed.
  """
  defmacro designate_user_entity(entity_type) do
    validate_placement!(__CALLER__)

    line = __CALLER__.line

    op =
      quote do
        %{op: :designate_user_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the first given entity type was renamed to the second, its table and every
  derived physical name following, existing data preserved.
  """
  defmacro rename_entity(old, new) do
    validate_placement!(__CALLER__)

    line = __CALLER__.line

    op =
      quote do
        %{op: :rename_entity, from: unquote(old), to: unquote(new), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records that the first given global role module was renamed to the second, existing
  grants following the label.
  """
  defmacro rename_role(old, new) do
    validate_placement!(__CALLER__)
    validate_global_role_args!([old, new], :rename_role, __CALLER__)
    line = __CALLER__.line

    op =
      quote do
        %{op: :rename_role, from: unquote(old), to: unquote(new), line: unquote(line)}
      end

    register(op, __CALLER__)
  end

  @doc """
  Records the placeholder op demanding human resolution of the given kind of detected
  change, with the detected facts as its payload.

  A migration file containing a resolve! op is a draft - verification, the check task,
  and the applier all refuse it until the line is replaced by the ops that express
  what happened.
  """
  defmacro resolve!(kind, payload \\ []) do
    validate_placement!(__CALLER__)

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

  # The environment the build is for. Mix knows it during compilation; HOLOGRAM_ENV may name
  # a different one, so it is the fallback only, and an exported HOLOGRAM_ENV=dev cannot let
  # a MIX_ENV=prod build through.
  defp build_env do
    if Code.ensure_loaded?(Mix) and Process.whereis(Mix.State) do
      # credo:disable-for-next-line Credo.Check.Warning.MixEnv
      Mix.env()
    else
      Hologram.env()
    end
  end

  # The side of a fn that didn't run read its attributes into snapshots nothing reads, which the
  # compiler would warn about.
  defp drop_snapshots(quoted, module) do
    snapshots =
      module
      |> Module.get_attribute(@snapshots_attribute)
      |> MapSet.new(fn {snapshot, _name, _line} -> snapshot end)

    Macro.prewalk(quoted, fn
      {:@, _meta, [{name, _name_meta, nil}]} = node ->
        if MapSet.member?(snapshots, name), do: Module.delete_attribute(module, name)

        node

      node ->
        node
    end)
  end

  # Aliases are expanded where the op is written: the op's code is placed in a function
  # defined at the end of the module, where an alias the module defines later would
  # otherwise change what an earlier op names. The expansion runs as though inside that
  # function, so naming an entity type is a runtime reference, as it would be written there,
  # rather than a compile-time dependency that recompiles the migration whenever the entity
  # module changes.
  defp expand_aliases(quoted, caller) do
    function_env = %{caller | function: {:__hologram_migration__, 0}}

    Macro.prewalk(quoted, fn
      # One headed by an attribute is left to the compiler: the head reads a snapshot that
      # isn't set while the op expands.
      {:__aliases__, _meta, [{:@, _attribute_meta, _args} | _rest]} = alias_ast ->
        alias_ast

      {:__aliases__, _meta, _segments} = alias_ast ->
        Macro.expand(alias_ast, function_env)

      node ->
        node
    end)
  end

  # One function per backfill, so its clause never lands apart from itself. The name is built from
  # a per-module counter, bounded by the source.
  # sobelow_skip ["DOS.BinToAtom"]
  defp hoist_fn_backfill(reading, index, body, env, functions) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    name = :"__backfill_#{index}__"

    if Module.defines?(env.module, {name, length(reading.args)}) do
      raise Hologram.CompileError,
        message:
          "#{name}/#{length(reading.args)} is the name a backfill fn runs under - rename the " <>
            "function",
        file: env.file,
        line: reading.env.line
    end

    definition = FieldAccess.define(:def, {name, [], reading.arg_asts}, do: body)

    function =
      quote do
        @doc false
        unquote(definition)
      end

    {Value.function_value(reading, env.module, name), [function | functions]}
  end

  # Options written as a list in place. Ones from a variable or a call are evaluated with the
  # op, and validate_ops!/2 checks a computed value they hold.
  # A fn's body is judged on its own once it's known to be Elixir - inside query(...) its calls are
  # words, whatever the file imports.
  defp imports_at(quoted, caller) do
    quoted
    |> Macro.prewalk(fn
      {:__hologram_fn_backfill__, meta, [index, value, _body]} ->
        {:__hologram_fn_backfill__, meta, [index, value, nil]}

      node ->
        node
    end)
    |> Value.local_calls()
    |> Map.new(&{&1, Macro.Env.lookup_import(caller, &1)})
  end

  defp lower_backfill(opts, caller) when is_list(opts) do
    Enum.map(opts, fn
      {:backfill, {:fn, _meta, _clauses} = value} -> {:backfill, read_fn_backfill(value, caller)}
      {:backfill, value} -> {:backfill, Value.lower(value, caller)}
      other -> other
    end)
  end

  defp lower_backfill(opts, _caller), do: opts

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
        opts: unquote(lower_backfill(opts, %{caller | line: line})),
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
        opts: unquote(lower_backfill(opts, %{caller | line: line})),
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

  defp member_op({:add_unique, meta, [fields]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_unique,
        entity: unquote(entity_type),
        fields: unquote(fields),
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
        changes: unquote(lower_backfill(changes, %{caller | line: line})),
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
        changes: unquote(lower_backfill(changes, %{caller | line: line})),
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

  defp member_op({:delete_unique, meta, [fields]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_unique,
        entity: unquote(entity_type),
        fields: unquote(fields),
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

  # Whether a fn is a query can hang on a function defined below the op, which only
  # __before_compile__ can see, so the op holds a placeholder until then. The query reading and the
  # body ride in it, so their attributes and aliases are read where the op is written, like any
  # op's, even though an Elixir body is emitted at the end of the module.
  defp read_fn_backfill(ast, caller) do
    reading = Value.read_fn(ast, caller)
    index = length(Module.get_attribute(caller.module, @fn_backfills_attribute))

    Module.put_attribute(caller.module, @fn_backfills_attribute, {index, reading})

    {:__hologram_fn_backfill__, [], [index, Value.fn_value(reading), reading.body]}
  end

  # An op is stored in the migration module's body, and the module's __hologram_migration__/0
  # returns the stored ops (see validate_placement!/1). What the op leaves in the body are the
  # snapshots of the attributes it reads (see snapshot_attribute_reads/3).
  defp register(quoted, caller) do
    {quoted, snapshots} = snapshot_attribute_reads(quoted, caller.module, [])

    Module.put_attribute(caller.module, @ops_attribute, expand_aliases(quoted, caller))

    Module.put_attribute(
      caller.module,
      @op_imports_attribute,
      {imports_at(quoted, caller), caller.line}
    )

    case Enum.reverse(snapshots) do
      [] -> nil
      assignments -> {:__block__, [], assignments}
    end
  end

  # Returns the ops with each fn settled, and the functions the Elixir ones run as.
  defp settle_fn_backfills(ops, env) do
    readings =
      env.module
      |> Module.get_attribute(@fn_backfills_attribute)
      |> Map.new()

    Macro.prewalk(ops, [], fn
      {:__hologram_fn_backfill__, _meta, [index, value, body]}, functions ->
        reading = Map.fetch!(readings, index)

        case Value.choose_fn!(reading, env) do
          :query ->
            drop_snapshots(body, env.module)

            {value, functions}

          :elixir ->
            drop_snapshots(value, env.module)

            hoist_fn_backfill(reading, index, body, env, functions)
        end

      node, functions ->
        {node, functions}
    end)
  end

  # An attribute an op reads is read where the op is written: the op's code is placed in a
  # function defined at the end of the module, where @name would read the value the body
  # assigned last. Each read becomes a read of a snapshot attribute of its own, set at the
  # op's line by an assignment the op leaves in the body. Snapshots are numbered per module,
  # so a recompile names them alike, and carry the attribute's name, which an error about
  # the value then shows. A quote is left alone - its @name is code, not a read.
  defp snapshot_attribute_reads({:quote, _meta, _args} = node, _module, snapshots) do
    {node, snapshots}
  end

  # The atom is built at compile time from an attribute name the migration's source spells and a
  # per-module counter - bounded by the source, never by anything a request carries.
  # sobelow_skip ["DOS.BinToAtom"]
  defp snapshot_attribute_reads(
         {:@, meta, [{name, _name_meta, context}]} = read,
         module,
         snapshots
       )
       when is_atom(name) and (is_atom(context) or context == []) do
    taken = Module.get_attribute(module, @snapshots_attribute)

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    snapshot = :"__hologram_migration_#{name}_#{length(taken)}__"

    Module.put_attribute(module, @snapshots_attribute, {snapshot, name, meta[:line]})

    assignment = {:@, meta, [{snapshot, meta, [read]}]}

    {{:@, meta, [{snapshot, meta, nil}]}, [assignment | snapshots]}
  end

  defp snapshot_attribute_reads({form, meta, args}, module, snapshots) do
    {[form, args], all_snapshots} = snapshot_attribute_reads([form, args], module, snapshots)

    {{form, meta, args}, all_snapshots}
  end

  defp snapshot_attribute_reads({left, right}, module, snapshots) do
    {[left, right], all_snapshots} = snapshot_attribute_reads([left, right], module, snapshots)

    {{left, right}, all_snapshots}
  end

  defp snapshot_attribute_reads(list, module, snapshots) when is_list(list) do
    Enum.map_reduce(list, snapshots, &snapshot_attribute_reads(&1, module, &2))
  end

  defp snapshot_attribute_reads(other, _module, snapshots), do: {other, snapshots}

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

  # An op's code is placed in a function defined at the end of the module, under the imports in
  # force there, so a call an import changes after the op would run another function than the one
  # written, and could store another value.
  defp validate_op_imports!(env) do
    for {imports, line} <- Module.get_attribute(env.module, @op_imports_attribute),
        {{name, arity} = call, at_op} <- imports,
        Macro.Env.lookup_import(env, call) != at_op do
      raise Hologram.CompileError,
        message:
          "a migration op calls #{name}/#{arity}, which an import changes between the op and " <>
            "the end of the module - put the import at the top of the module",
        file: env.file,
        line: line
    end

    :ok
  end

  # Checked before anything else an op macro does, so an op in the wrong place is told so
  # first, whatever else is wrong with it. Anywhere but a migration module's body - a function,
  # a module nested in a migration or one that only imports the vocabulary, a script - the op
  # has nowhere to go, so it is refused rather than dropped.
  defp validate_placement!(caller) do
    if not (module_body?(caller) and Module.has_attribute?(caller.module, @ops_attribute)) do
      raise Hologram.CompileError,
        message:
          "migration ops go in the body of a module that uses Hologram.Migration - " <>
            "#{Path.relative_to_cwd(caller.file)}:#{caller.line}"
    end
  end

  # An op is recorded however the module body runs around it, but its attribute snapshots are
  # taken only where the body runs: one left unset means the op sits in a branch that never
  # runs, and its value would silently be nil.
  defp validate_snapshots_taken!(env) do
    set_attributes = Module.attributes_in(env.module)

    untaken =
      env.module
      |> Module.get_attribute(@snapshots_attribute)
      |> Enum.reject(fn {snapshot, _name, _line} -> snapshot in set_attributes end)
      |> Enum.reverse()

    if untaken != [] do
      file = Path.relative_to_cwd(env.file)

      lines =
        Enum.map_join(untaken, "\n", fn {_snapshot, name, line} ->
          "  #{file}:#{line} - reads @#{name}"
        end)

      raise Hologram.CompileError,
        message:
          "a migration op reads an attribute in module-body code that never runs, so the " <>
            "op would record nil for it - ops are recorded wherever they are written, so " <>
            "write them outside if, case and the like:\n" <> lines
    end
  end
end
