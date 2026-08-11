defmodule Hologram.DB.QueryCache do
  @moduledoc false

  use GenServer

  alias Hologram.Compiler.QueryExtractor
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.DB.SchemaReconciler
  alias Hologram.DB.SortKey
  alias Hologram.Policy
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

  Raises Hologram.CompileError when a registered query reads an entity type
  declaring no allow lines - such a query is statically dead, because default
  deny returns it no rows for any session.
  """
  @spec reload() :: :ok
  def reload do
    if Process.whereis(DB) do
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

  defp dead_query_message(module, dead_entity_types) do
    listing = Enum.map_join(dead_entity_types, ", ", &inspect/1)
    declare_verb = if length(dead_entity_types) == 1, do: "declares", else: "declare"

    "the registered query in #{inspect(module)} reads #{listing}, which #{declare_verb} no allow lines - default deny returns no rows to any session. Add allow lines, or drop the query."
  end

  # The registered queries' ordered pairs enrich the mapping with sort-key
  # companions - the cache owns this derivation because extraction needs no
  # mapping and the cache boots right after the database. With no pairs the boot
  # mapping stands, and orphaned companions drop on the next model
  # reconciliation, which targets the plain mapping.
  defp ensure_mapping(terms) do
    ordered_pairs = Registry.ordered_string_pairs(terms)

    if MapSet.size(ordered_pairs) == 0 do
      DB.mapping()
    else
      mapping = Mapper.derive!(Reflection.list_entities(), ordered_pairs)
      :persistent_term.put(DB.mapping_key(), mapping)

      reconcile_result = SchemaReconciler.reconcile(DB.reconciliation_context())
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
    module_queries = Enum.map(modules, &{&1, QueryExtractor.extract_module_queries(&1)})

    Enum.each(module_queries, &validate_readable_queries!/1)

    terms = Enum.flat_map(module_queries, fn {_module, module_terms} -> module_terms end)
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

  defp queried_entity_types(term) do
    nested_types =
      term.include
      |> Map.values()
      |> Enum.flat_map(&queried_entity_types/1)

    Enum.uniq([term.entity | nested_types])
  end

  # A registered query naming an entity type with no allow lines - as its root or as an
  # include target - is statically dead: the policied read path composes default deny
  # into every statement, so no session ever receives a row from it.
  defp validate_readable_queries!({module, module_terms}) do
    Enum.each(module_terms, fn term ->
      case Policy.dead_entity_types(queried_entity_types(term)) do
        [] ->
          :ok

        dead_entity_types ->
          raise Hologram.CompileError, message: dead_query_message(module, dead_entity_types)
      end
    end)
  end
end
