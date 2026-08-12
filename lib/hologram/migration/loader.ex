defmodule Hologram.Migration.Loader do
  @moduledoc false

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

  defp statements({:__block__, _meta, statements}), do: statements

  defp statements(single_statement), do: [single_statement]

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
