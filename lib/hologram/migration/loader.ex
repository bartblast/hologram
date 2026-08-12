defmodule Hologram.Migration.Loader do
  @moduledoc false

  alias Hologram.Reflection

  # A migration file name is its version - 14 UTC timestamp digits, nothing else. The
  # filesystem then enforces version uniqueness, and a directory listing is the ordered
  # history.
  @file_name_regex ~r/^\d{14}\.exs$/

  # The top-level vocabulary, as imported by the header - a migration file holds these
  # statements and nothing else, so imperative code cannot enter the format.
  @flat_ops [
    :add_role,
    :change_entity,
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
  and :ops. A directory that does not exist holds no migrations. Every entry raises
  unless its name is a 14-digit timestamp with the .exs extension.
  """
  @spec load_dir!(String.t()) :: list(%{atom => any})
  def load_dir!(dir) do
    case File.ls(dir) do
      {:error, :enoent} ->
        []

      {:ok, file_names} ->
        file_names
        |> Enum.sort()
        |> Enum.map(&load_file!(&1, dir))
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

  defp load_file!(file_name, dir) do
    validate_file_name!(file_name, dir)

    path = Path.join(dir, file_name)

    ops =
      path
      |> File.read!()
      |> load_string!(path)

    %{version: Path.rootname(file_name), path: path, ops: ops}
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
end
