defmodule Hologram.Migration.Loader do
  @moduledoc false

  alias Hologram.Reflection

  # A migration file name is its version - 14 UTC timestamp digits, nothing else. The
  # filesystem then enforces version uniqueness, and a directory listing is the ordered
  # history.
  @file_name_regex ~r/^\d{14}\.exs$/

  # The top-level vocabulary, as imported by the header - a migration file holds these
  # statements and nothing else, so imperative code cannot enter the format.
  #
  # TODO: only the statement HEADS are checked, so an argument could still carry an
  # expression that runs at load. Walking the argument AST for literals closes the gap
  # in the "migration files hold no imperative code" claim - the trust class is the same
  # as any source file meanwhile, which is why evaluating them is sound.
  @flat_ops [
    :add_role,
    :change_entity,
    :change_role,
    :create_entity,
    :delete_entity,
    :delete_role,
    :delete_role_grants,
    :designate_user_entity,
    :rename_entity,
    :rename_role,
    :resolve!
  ]

  @doc """
  Returns the migrations of the given directory, ordered by version.

  Each migration is a map with :version (the file name without the extension), :path,
  and :ops. A directory that does not exist holds no migrations, and a directory that
  cannot be read raises naming it.

  Every `.exs` entry raises unless its name is a 14-digit timestamp - a misnamed
  migration is never skipped quietly, because skipping one silently is how a database
  ends up a file behind. Dotfiles and other extensions are left alone: `.gitkeep` keeps
  the directory in version control before the first migration exists, and editors and
  operating systems leave their own droppings.
  """
  @spec load_dir!(String.t()) :: list(%{atom => any})
  def load_dir!(dir) do
    case File.ls(dir) do
      {:ok, file_names} ->
        file_names
        |> Enum.sort()
        |> Enum.filter(&migration_file?/1)
        |> Enum.map(&load_file!(Path.join(dir, &1)))

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise "cannot read the migrations directory #{dir} - " <>
                "#{:file.format_error(reason)}"
    end
  end

  @doc """
  Returns the migrations the given migration modules define, ordered by version.

  Each migration is a map with :version, :path, :ops and :module. Raises naming both files
  when two modules define the same version - one directory holds every migration of an app,
  but an umbrella's apps each have their own.
  """
  @spec from_modules!(list(module)) :: list(%{atom => any})
  def from_modules!(modules) do
    migrations =
      modules
      |> Enum.map(&Map.put(&1.__hologram_migration__(), :module, &1))
      |> Enum.sort_by(& &1.version)

    migrations
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.each(&validate_distinct_versions!/1)

    migrations
  end

  @doc """
  Returns the migrations the project's migration modules define, ordered by version (see
  `from_modules!/1`).
  """
  @spec list!() :: list(%{atom => any})
  def list! do
    from_modules!(Reflection.list_migrations())
  end

  @doc """
  Returns the migration of the given file: a map with :version (the file name without the
  extension), :path, and :ops. Raises unless the file name is a 14-digit timestamp with the
  `.exs` extension, or when the file does not load (see `load_string!/2`) or references an
  entity type by a name it renames away (see `verify_rename_order!/2`).
  """
  @spec load_file!(String.t()) :: %{atom => any}
  def load_file!(path) do
    file_name = Path.basename(path)

    validate_file_name!(file_name, Path.dirname(path))

    ops =
      path
      |> File.read!()
      |> load_string!(path)

    verify_rename_order!(ops, path)

    %{version: Path.rootname(file_name), path: path, ops: ops}
  end

  @doc """
  Returns the absolute path of the project's migrations directory, `app/migrations/` in the
  OTP app's directory.

  Raises unless the project compiles `app/migrations/`, through it or a directory holding
  it, like `app/`: the migration modules there would be left out of the build without a
  word, the history would read as empty, and the generator would write the whole of it
  again. Requires a Mix project context.
  """
  @spec migrations_dir!() :: String.t()
  def migrations_dir! do
    app_dir = Reflection.otp_app_dir()
    migrations_dir = Path.join([app_dir, "app", "migrations"])

    compiled? =
      app_dir
      |> project_elixirc_paths()
      |> Enum.map(&Path.expand(&1, app_dir))
      |> Enum.any?(&(migrations_dir == &1 or String.starts_with?(migrations_dir, &1 <> "/")))

    if not compiled? do
      raise "the project does not compile app/migrations/, where migration modules live - " <>
              "add \"app\" to elixirc_paths in mix.exs"
    end

    migrations_dir
  end

  @doc """
  Returns the ops of the migration file with the given contents, in file order.

  The file must start with the `use Hologram.Migration` header, and every statement
  after it must be a migration op - anything else raises, naming the file and the line.
  """
  @spec load_string!(String.t(), String.t()) :: list(%{atom => any})
  # Migration files are the app's own code artifacts - generated into priv/, reviewed
  # in PRs, and shipped with the release like any source file. Evaluating them is the
  # format's designed behavior, and whoever could plant a malicious migration could
  # plant a malicious module instead.
  # sobelow_skip ["RCE.CodeModule"]
  def load_string!(contents, path) do
    [header | op_statements] =
      contents
      |> Code.string_to_quoted!(file: path)
      |> statements()
      |> validate_header!(path)

    Enum.each(op_statements, &validate_op_statement!(&1, path))

    {ops, _binding} = Code.eval_quoted({:__block__, [], [header, op_statements]}, [], file: path)

    List.flatten(ops)
  end

  @doc """
  Returns the resolve! ops of the given op list - the unresolved questions that make a
  migration file a draft.
  """
  @spec unresolved(list(%{atom => any})) :: list(%{atom => any})
  def unresolved(ops) do
    Enum.filter(ops, &(&1.op == :resolve!))
  end

  @doc """
  Validates that no op of the given migration file references an entity type by a name
  the file renames away.

  Sequential logs admit equivalent orderings, and only the misleading one is illegal:
  once a file renames an entity type, its old name may not appear anywhere except the
  rename op itself, so every line cross-references the current model instead of a name
  that no longer exists. Returns :ok, or raises naming the offending line and the fix.
  """
  @spec verify_rename_order!(list(%{atom => any}), String.t()) :: :ok
  def verify_rename_order!(ops, path) do
    renames = Enum.filter(ops, &(&1.op == :rename_entity))

    Enum.each(renames, fn rename ->
      Enum.each(ops, &verify_rename_reference!(&1, rename, path))
    end)

    :ok
  end

  defp migration_file?(file_name) do
    not String.starts_with?(file_name, ".") and String.ends_with?(file_name, ".exs")
  end

  # Mix's own default when a project sets no elixirc_paths. An umbrella's app is read
  # from its own project, the one its config lives in.
  defp project_elixirc_paths(app_dir) do
    config =
      case Mix.Project.apps_paths() do
        nil ->
          Mix.Project.config()

        _apps_paths ->
          Mix.Project.in_project(Reflection.otp_app(), app_dir, fn _module ->
            Mix.Project.config()
          end)
      end

    Keyword.get(config, :elixirc_paths, ["lib"])
  end

  defp references_entity?(op, module) do
    changes = Map.get(op, :changes, [])
    changed_relationship_type = Keyword.get(changes, :type)

    Map.get(op, :entity) == module or
      Map.get(op, :from) == module or
      relationship_target?(Map.get(op, :type), module) or
      relationship_target?(changed_relationship_type, module)
  end

  defp relationship_target?(type, module) do
    type == module or type == [module]
  end

  defp statements({:__block__, _meta, statements}), do: statements

  defp statements(single_statement), do: [single_statement]

  defp validate_distinct_versions!([%{version: version} = first, %{version: version} = second]) do
    raise Hologram.CompileError,
      message:
        "migration version #{version} is defined twice - " <>
          "#{inspect(first.module)} (#{first.path}) and " <>
          "#{inspect(second.module)} (#{second.path})"
  end

  defp validate_distinct_versions!(_pair), do: :ok

  defp validate_file_name!(file_name, dir) do
    if not Regex.match?(@file_name_regex, file_name) do
      raise Hologram.CompileError,
        message:
          "invalid migration file name #{Path.join(dir, file_name)} - " <>
            "a migration file is named after its version: 14 timestamp digits with the " <>
            "\".exs\" extension, e.g. \"20260813091500.exs\""
    end
  end

  defp validate_header!(
         [{:use, _meta, [{:__aliases__, _alias_meta, [:Hologram, :Migration]}]} | _rest] =
           statements,
         _path
       ) do
    statements
  end

  defp validate_header!(_statements, path) do
    raise Hologram.CompileError,
      message: "migration file #{path} must start with the use Hologram.Migration header"
  end

  defp validate_op_statement!({name, _meta, args}, _path)
       when name in @flat_ops and is_list(args) do
    :ok
  end

  defp validate_op_statement!(statement, path) do
    line =
      case statement do
        {_name, meta, _args} when is_list(meta) -> Keyword.get(meta, :line, 0)
        _other -> 0
      end

    raise Hologram.CompileError,
      message: "migration files contain only migration ops - #{path}:#{line}"
  end

  defp verify_rename_reference!(op, rename, path) do
    if op != rename and references_entity?(op, rename.from) do
      raise Hologram.CompileError,
        message:
          "#{path}:#{op.line} references #{inspect(rename.from)}, " <>
            "renamed on line #{rename.line} - " <>
            "move the rename first and use #{inspect(rename.to)}"
    end
  end
end
