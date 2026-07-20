defmodule Hologram.Database.Schema do
  @moduledoc false

  @doc """
  Returns the physical schema term derived from the given mapping.

  The term is plain data keyed by physical names - the shape both sides of the
  reconciliation comparison share. :tables maps each table name (entity tables and
  join tables alike) to its definition: :columns (column name to %{type:, collation:,
  null:}) and :primary_key (%{columns:, constraint:}). Join table columns are fixed:
  source_id/target_id uuid NOT NULL with a composite primary key.
  """
  @spec from_mapping(%{module => %{atom => any}}) :: %{atom => any}
  def from_mapping(mapping) do
    tables =
      mapping
      |> Enum.flat_map(fn {_entity_type, entity_mapping} ->
        [entity_table(entity_mapping) | Enum.map(entity_mapping.join_tables, &join_table/1)]
      end)
      |> Map.new()

    %{tables: tables}
  end

  defp entity_table(entity_mapping) do
    columns =
      Map.new(entity_mapping.columns, fn column ->
        {column.name, %{type: column.sql_type, collation: column.collation, null: column.null}}
      end)

    {entity_mapping.table,
     %{
       columns: columns,
       primary_key: %{columns: ["id"], constraint: entity_mapping.pk_constraint}
     }}
  end

  defp join_table(join_table) do
    columns = %{
      "source_id" => %{type: "uuid", collation: nil, null: false},
      "target_id" => %{type: "uuid", collation: nil, null: false}
    }

    {join_table.name,
     %{
       columns: columns,
       primary_key: %{
         columns: ["source_id", "target_id"],
         constraint: join_table.pk_constraint
       }
     }}
  end
end
