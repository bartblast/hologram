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
        |> Enum.map(&load_file!(&1, dir))

      {:error, :enoent} ->
        []

      {:error, reason} ->
        raise "cannot read the migrations directory #{dir} - " <>
                "#{:file.format_error(reason)}"
    end
  end

  @doc """
  Returns the absolute path of the project's migrations directory.
  """
  @spec migrations_dir() :: String.t()
  def migrations_dir do
    Path.join([Reflection.otp_app_priv_dir(), "hologram", "migrations"])
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

  defp load_file!(file_name, dir) do
    validate_file_name!(file_name, dir)

    path = Path.join(dir, file_name)

    ops =
      path
      |> File.read!()
      |> load_string!(path)

    verify_rename_order!(ops, path)

    %{version: Path.rootname(file_name), path: path, ops: ops}
  end

  defp migration_file?(file_name) do
    not String.starts_with?(file_name, ".") and String.ends_with?(file_name, ".exs")
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
