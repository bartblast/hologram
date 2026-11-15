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
