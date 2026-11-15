defmodule Hologram.Migration.Loader do
  @moduledoc false

  alias Hologram.Reflection

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

    if not compiles_migrations_dir?(app_dir, project_elixirc_paths(app_dir)) do
      raise "the project does not compile app/migrations/, where migration modules live - " <>
              "add \"app\" to elixirc_paths in mix.exs"
    end

    migrations_dir(app_dir)
  end

  @doc """
  Validates that the project compiles the migration files the given app directory's
  `app/migrations/` holds - by default, the OTP app's. Returns :ok when it does, or when
  the directory holds no migration file.

  Run by the Hologram compiler on every build, a release's included: a build whose
  elixirc_paths leave the directory out, perhaps for one environment only, would ship
  without its migrations, and the app would then refuse to boot with its model uncovered,
  naming no cause. Raises Hologram.CompileError naming the directory instead. Requires a
  Mix project context.

  Only the OTP app's directory is checked - where the generator writes. An umbrella sibling
  or a dependency holding migrations of its own is checked when its own build runs this.
  """
  @spec validate_migrations_compiled!(String.t()) :: :ok
  def validate_migrations_compiled!(app_dir \\ Reflection.otp_app_dir()) do
    # Read only when there is something to check: in an umbrella, reading the paths enters
    # the app's project, and live reload runs this check on every reload.
    if migration_files?(app_dir) do
      validate_migrations_compiled!(app_dir, project_elixirc_paths(app_dir))
    else
      :ok
    end
  end

  @doc """
  Validates that the given elixirc_paths compile the migration files of the given app
  directory's `app/migrations/` (see `validate_migrations_compiled!/1`).
  """
  @spec validate_migrations_compiled!(String.t(), list(String.t())) :: :ok
  def validate_migrations_compiled!(app_dir, elixirc_paths) do
    if migration_files?(app_dir) and not compiles_migrations_dir?(app_dir, elixirc_paths) do
      raise Hologram.CompileError,
        message:
          "app/migrations/ holds migration files, but this build does not compile the " <>
            "directory, so the app would ship without its migrations - add \"app\" to " <>
            "elixirc_paths in mix.exs, for every environment"
    end

    :ok
  end

  @doc """
  Validates that none of the given migrations is a draft, in a build of the given
  environment.

  A draft compiles in dev and test, so the generator, which compiles the app before it
  reads the history, can still read it and ask for its answers. Any other build is headed
  for a deployment, and an unanswered question must not reach one. Returns :ok, or raises
  Hologram.CompileError naming each resolve! op's file and line.
  """
  @spec validate_resolved!(list(%{atom => any}), atom) :: :ok
  def validate_resolved!(migrations, env) do
    unresolved = unresolved_entries(migrations)

    if unresolved != [] and env not in [:dev, :test] do
      raise Hologram.CompileError,
        message:
          "the migration draft is not resolved yet, and a #{env} build refuses it:\n" <>
            unresolved_lines(unresolved) <>
            "\nWrite the ops that express what happened, delete the resolve! lines, " <>
            "then finalize with mix holo.gen.migration."
    end

    :ok
  end

  @doc """
  Validates that none of the project's migrations is a draft, in a build of the given
  environment (see `validate_resolved!/2`).

  Reads the compiled migration modules, so it covers a beam the build reuses from another
  environment, whose compile never refused it: under `build_per_environment: false` one
  build directory serves every environment. Lists the modules only in a build that refuses
  drafts.
  """
  @spec validate_project_resolved!(atom) :: :ok
  def validate_project_resolved!(env) when env in [:dev, :test], do: :ok

  def validate_project_resolved!(env), do: validate_resolved!(list!(), env)

  @doc """
  Returns the resolve! ops of the given op list - the unresolved questions that make a
  migration file a draft.
  """
  @spec unresolved(list(%{atom => any})) :: list(%{atom => any})
  def unresolved(ops) do
    Enum.filter(ops, &(&1.op == :resolve!))
  end

  @doc """
  Returns the lines listing the given unresolved entries (see `unresolved_entries/1`), one
  per op with its location and kind, as the refusals of a draft print them.
  """
  @spec unresolved_lines(list({String.t(), %{atom => any}})) :: String.t()
  def unresolved_lines(entries) do
    Enum.map_join(entries, "\n", fn {path, op} -> "  #{path}:#{op.line} - #{inspect(op.kind)}" end)
  end

  @doc """
  Returns the resolve! ops of the given migrations, each with the path of its migration,
  in history order.
  """
  @spec unresolved_entries(list(%{atom => any})) :: list({String.t(), %{atom => any}})
  def unresolved_entries(migrations) do
    Enum.flat_map(migrations, fn migration ->
      Enum.map(unresolved(migration.ops), &{migration.path, &1})
    end)
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

  # Any compiled directory that is app/migrations or holds it compiles the migrations.
  defp compiles_migrations_dir?(app_dir, elixirc_paths) do
    migrations_dir = migrations_dir(app_dir)

    elixirc_paths
    |> Enum.map(&Path.expand(&1, app_dir))
    |> Enum.any?(&(migrations_dir == &1 or String.starts_with?(migrations_dir, &1 <> "/")))
  end

  defp migrations_dir(app_dir), do: Path.join([app_dir, "app", "migrations"])

  defp migration_files?(app_dir) do
    dir = migrations_dir(app_dir)

    case File.ls(dir) do
      {:ok, file_names} -> Enum.any?(file_names, &String.ends_with?(&1, ".ex"))
      {:error, _reason} -> false
    end
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

  defp validate_distinct_versions!([%{version: version} = first, %{version: version} = second]) do
    raise Hologram.CompileError,
      message:
        "migration version #{version} is defined twice - " <>
          "#{inspect(first.module)} (#{first.path}) and " <>
          "#{inspect(second.module)} (#{second.path})"
  end

  defp validate_distinct_versions!(_pair), do: :ok

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
