defmodule Hologram.Database.QueryCompiler do
  @moduledoc false

  alias Hologram.Database.Mapper

  @data_schema "hologram_data"

  @doc """
  Compiles the given normalized query term into a SQL statement using the given
  physical name mapping.

  Returns a map with :sql (the statement string, identifiers quoted and
  schema-qualified) and :params (the bind slots in placeholder order - empty for
  queries without predicates). Column selection follows the mapping's physical
  column order.
  """
  @spec compile(%{atom => any}, %{module => %{atom => any}}) :: %{atom => any}
  def compile(term, mapping) do
    %{table: table, columns: columns} = Map.fetch!(mapping, term.entity)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))

    %{
      params: [],
      sql: "SELECT #{column_list} FROM #{qualified_table(table)}"
    }
  end

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end
end
