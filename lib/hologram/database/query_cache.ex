defmodule Hologram.Database.QueryCache do
  @moduledoc false

  use GenServer

  alias Hologram.Compiler.QueryExtractor
  alias Hologram.Database
  alias Hologram.Database.Connection
  alias Hologram.Database.Mapper
  alias Hologram.Database.QueryCompiler
  alias Hologram.Database.SchemaReconciler
  alias Hologram.Database.SortKey
  alias Hologram.Query.Registry
  alias Hologram.Reflection

  @doc """
  Returns the modules swept for registered queries.
  """
  @callback component_modules() :: list(module)

  @doc """
  Returns the key of the persistent term used by the query cache registered process.
  """
  @callback persistent_term_key() :: any

  @doc """
  Starts query cache process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl GenServer
  def init(nil) do
    populate()
    {:ok, nil}
  end

  @doc """
  Returns the modules swept for registered queries - all component modules in the project.
  """
  @spec component_modules() :: list(module)
  def component_modules do
    Reflection.list_components()
  end

  @doc """
  Returns all query cache entries - a map from query content ID to the registry
  entry extended with the query's compiled form under the :compiled key.
  """
  @spec entries() :: %{String.t() => %{atom => any}}
  def entries do
    :persistent_term.get(impl().persistent_term_key()).entries
  end

  @doc """
  Returns {:ok, entry} for the given query content ID, or :error when no query
  with the given ID is registered.
  """
  @spec fetch(String.t()) :: {:ok, %{atom => any}} | :error
  def fetch(id) do
    Map.fetch(entries(), id)
  end

  @doc """
  Returns the implementation of the query cache's persistent term key.
  """
  @spec persistent_term_key() :: any
  def persistent_term_key do
    __MODULE__
  end

  @doc """
  Returns the ordered argument names of the parameterized from_query capture
  declared for the given component prop, or nil when the prop declares none.
  """
  @spec prop_params(module, atom) :: list(atom | nil) | nil
  def prop_params(module, prop_name) do
    key = impl().persistent_term_key()

    Map.get(:persistent_term.get(key).prop_params, {module, prop_name})
  end

  @doc """
  Rebuilds the query cache from the current component modules and mapping - the
  live-reload path after a dev code change. A no-op when the database is not
  running (no entities declared at boot). Returns :ok.
  """
  @spec reload() :: :ok
  def reload do
    if Process.whereis(Database) do
      populate()
    end

    :ok
  end

  # The transaction and row locks serialize the backfill against concurrent
  # entity updates - a live-reload backfill runs while the endpoint serves, and
  # an update slipping between the read and the companion write would get its
  # fresh companion value overwritten from the stale source read.
  # sobelow_skip ["SQL.Query"]
  defp backfill_column!(table, companion_name, source_name) do
    select_sql =
      ~s(SELECT "id", #{Mapper.quote_identifier(source_name)} FROM #{qualified_table(table)} FOR UPDATE)

    update_sql =
      ~s(UPDATE #{qualified_table(table)} SET #{Mapper.quote_identifier(companion_name)} = $1 WHERE "id" = $2)

    {:ok, :ok} =
      Connection.transaction(fn ->
        {:ok, %{rows: rows}} = Connection.query(select_sql, [])

        Enum.each(rows, fn
          [_id, nil] ->
            :ok

          [id, value] ->
            {:ok, _result} = Connection.query(update_sql, [SortKey.compute(value), id])
        end)
      end)

    :ok
  end

  defp backfill_sort_keys!(ops, mapping) do
    ops
    |> Enum.filter(&match?(%{op: :add_column}, &1))
    |> Enum.each(&maybe_backfill_op!(&1, mapping))
  end

  # The registered queries' ordered pairs enrich the mapping with sort-key
  # companions - the cache owns this derivation because extraction needs no
  # mapping and the cache boots right after the database. With no pairs the boot
  # mapping stands, and orphaned companions drop on the next model
  # reconciliation, which targets the plain mapping.
  defp ensure_mapping(terms) do
    ordered_pairs = Registry.ordered_string_pairs(terms)

    if MapSet.size(ordered_pairs) == 0 do
      Database.mapping()
    else
      mapping = Mapper.derive!(Reflection.list_entities(), ordered_pairs)
      :persistent_term.put(Database.mapping_key(), mapping)

      reconcile_result = SchemaReconciler.reconcile(Database.reconciliation_context())
      backfill_sort_keys!(reconcile_result.ops, mapping)

      mapping
    end
  end

  defp impl do
    Application.get_env(:hologram, :query_cache_impl, __MODULE__)
  end

  defp maybe_backfill_op!(op, mapping) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, table_mapping} -> table_mapping.table == op.table end)

    column = Enum.find(entity_mapping.columns, &(&1.name == op.column))

    case column do
      %{source: {:sort_key, attribute_name}} ->
        source_column =
          Enum.find(entity_mapping.columns, &(&1.source == {:attribute, attribute_name}))

        backfill_column!(entity_mapping.table, column.name, source_column.name)

      _other_column ->
        :ok
    end
  end

  defp populate do
    modules = impl().component_modules()
    terms = QueryExtractor.extract_queries(modules)
    mapping = ensure_mapping(terms)

    entries =
      terms
      |> Registry.build()
      |> Map.new(fn {id, entry} ->
        {id, Map.put(entry, :compiled, QueryCompiler.compile(entry.term, mapping))}
      end)

    prop_params =
      modules
      |> Enum.flat_map(fn module ->
        module
        |> QueryExtractor.extract_prop_params()
        |> Enum.map(fn {prop_name, param_names} -> {{module, prop_name}, param_names} end)
      end)
      |> Map.new()

    data = %{entries: entries, prop_params: prop_params}

    :persistent_term.put(impl().persistent_term_key(), data)
  end

  defp qualified_table(table) do
    ~s("hologram_data".#{Mapper.quote_identifier(table)})
  end
end
