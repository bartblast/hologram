defmodule Hologram.Database.Schema do
  @moduledoc false

  @doc """
  Returns the physical schema term derived from the given mapping.

  The term is plain data keyed by physical names - the shape both sides of the
  reconciliation comparison share. :tables maps each table name (entity tables and
  join tables alike) to its definition: :columns (column name to %{type:, collation:,
  null:}), :primary_key (%{columns:, constraint:}), :foreign_keys (owning column name
  to %{references:, on_delete:, constraint:}), and :indexes (index name to %{columns:}).
  :enum_types maps each derived enum type name to its values in declaration order.
  Join table columns are fixed: source_id/target_id uuid NOT NULL with a composite
  primary key, both columns FK ON DELETE RESTRICT, and the reverse index over
  (target_id, source_id).
  """
  @spec from_mapping(%{module => %{atom => any}}) :: %{atom => any}
  def from_mapping(mapping) do
    tables =
      mapping
      |> Enum.flat_map(fn {_entity_type, entity_mapping} ->
        [entity_table(entity_mapping) | Enum.map(entity_mapping.join_tables, &join_table/1)]
      end)
      |> Map.new()

    enum_types =
      mapping
      |> Enum.flat_map(fn {_entity_type, entity_mapping} ->
        entity_mapping.columns
        |> Enum.filter(& &1.enum_values)
        |> Enum.map(&{&1.sql_type, &1.enum_values})
      end)
      |> Map.new()

    %{tables: tables, enum_types: enum_types}
  end

  defp entity_table(entity_mapping) do
    columns =
      Map.new(entity_mapping.columns, fn column ->
        {column.name, %{type: column.sql_type, collation: column.collation, null: column.null}}
      end)

    reference_columns = Enum.filter(entity_mapping.columns, & &1.references)

    foreign_keys =
      Map.new(reference_columns, fn column ->
        {column.name,
         %{
           references: column.references,
           on_delete: :restrict,
           constraint: column.fk_constraint
         }}
      end)

    indexes = Map.new(reference_columns, &{&1.fk_index, %{columns: [&1.name]}})

    {entity_mapping.table,
     %{
       columns: columns,
       primary_key: %{columns: ["id"], constraint: entity_mapping.pk_constraint},
       foreign_keys: foreign_keys,
       indexes: indexes
     }}
  end

  defp join_table(join_table) do
    columns = %{
      "source_id" => %{type: "uuid", collation: nil, null: false},
      "target_id" => %{type: "uuid", collation: nil, null: false}
    }

    foreign_keys = %{
      "source_id" => %{
        references: join_table.source_table,
        on_delete: :restrict,
        constraint: join_table.source_fk_constraint
      },
      "target_id" => %{
        references: join_table.target_table,
        on_delete: :restrict,
        constraint: join_table.target_fk_constraint
      }
    }

    {join_table.name,
     %{
       columns: columns,
       primary_key: %{
         columns: ["source_id", "target_id"],
         constraint: join_table.pk_constraint
       },
       foreign_keys: foreign_keys,
       indexes: %{join_table.reverse_index => %{columns: ["target_id", "source_id"]}}
     }}
  end
end
