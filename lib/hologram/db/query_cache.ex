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
  alias Hologram.Entity
  alias Hologram.Migrator
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
  Returns the term the given window downloads, or nil when no registered query downloads it.

  Windows are shared: several queries choosing among the same rows name one window between them,
  and this is what the sync layer runs for all of them.
  """
  @spec window(String.t()) :: %{atom => any} | nil
  def window(window_id) do
    :persistent_term.get(impl().persistent_term_key()).windows[window_id]
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
  declaring no allow lines - default deny makes it statically dead, returning
  no rows when it is the query's root and no embedded row when it is an
  include target.
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

  defp dead_include_message(module, dead_entity_types) do
    "the registered query in #{inspect(module)} includes #{listing(dead_entity_types)}, which #{declare_verb(dead_entity_types)} no allow lines - default deny leaves the embed empty in every row. Add allow lines, or drop the include."
  end

  defp dead_root_message(module, dead_entity_types) do
    "the registered query in #{inspect(module)} reads #{listing(dead_entity_types)}, which #{declare_verb(dead_entity_types)} no allow lines - default deny returns no rows to any session. Add allow lines, or drop the query."
  end

  defp declare_verb([_single_entity_type]), do: "declares"

  defp declare_verb(_entity_types), do: "declare"

  # A reconciliation-managed database converges wholesale from the enriched mapping. A
  # migration-managed one takes model changes only through its migration history - the
  # query-derived companions are the one part that rides no migration, so only they
  # converge here.
  defp converge_artifacts(mapping) do
    if migrations_managed?() do
      Migrator.reconcile_artifacts(mapping)
    else
      SchemaReconciler.reconcile(DB.reconciliation_context()).ops
    end
  end

  # The registered queries' sort-key attributes enrich the mapping with sort-key
  # companions - the cache owns this derivation because extraction needs no
  # mapping and the cache boots right after the database. With no pairs the boot
  # mapping stands - a reconciliation-managed database drops orphaned companions
  # on the next model reconciliation, which targets the plain mapping, while a
  # migration-managed one drops them here, the one convergence that reaches them.
  defp ensure_mapping(terms) do
    sort_key_attributes = Registry.sort_key_attributes(terms)

    if MapSet.size(sort_key_attributes) == 0 do
      mapping = DB.mapping()

      if migrations_managed?() do
        Migrator.reconcile_artifacts(mapping)
      end

      mapping
    else
      mapping = Mapper.derive!(Reflection.list_entities(), sort_key_attributes)
      :persistent_term.put(DB.mapping_key(), mapping)

      ops = converge_artifacts(mapping)
      backfill_sort_keys!(ops, mapping)

      mapping
    end
  end

  defp impl do
    Application.get_env(:hologram, :query_cache_impl, __MODULE__)
  end

  defp included_entity_types(term) do
    term.include
    |> Map.values()
    |> Enum.flat_map(&queried_entity_types/1)
    |> Enum.uniq()
  end

  defp listing(entity_types) do
    Enum.map_join(entity_types, ", ", &inspect/1)
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

  # The environment selects the schema mechanism, the same rule the database boots by -
  # asking the database instead would mean reading the marker of a database that
  # reconciliation has not created yet, which is exactly the state this runs in.
  defp migrations_managed? do
    Hologram.env() not in [:dev, :test]
  end

  defp populate do
    modules = impl().component_modules()
    module_queries = Enum.map(modules, &{&1, QueryExtractor.extract_module_queries(&1)})

    Enum.each(module_queries, &validate_readable_queries!/1)
    Enum.each(module_queries, &validate_client_evaluable_queries!/1)

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

    windows = Map.new(entries, fn {_id, entry} -> {entry.window_id, entry.window} end)

    data = %{entries: entries, prop_params: prop_params, windows: windows}

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

  defp server_only_listing(references) do
    Enum.map_join(references, ", ", fn {entity_type, names} ->
      "#{inspect(entity_type)} #{Enum.map_join(names, ", ", &inspect/1)}"
    end)
  end

  defp server_only_query_message(module, references) do
    "the registered query in #{inspect(module)} filters or orders on server_only attributes (#{server_only_listing(references)}) - the client never holds those values, so it could not evaluate the reference locally. Drop the reference, or read the rows through the trusted backend API."
  end

  # Pairs each term entity with the server-only attributes its own filter and order_by name,
  # walking include sub-terms so a reference nested under an include is reached too.
  defp server_only_references(term) do
    server_only_names = Entity.server_only_attribute_names(term.entity)
    filter_names = Enum.map(term.filter, fn {name, _operator, _value} -> name end)
    order_by_names = Enum.map(term.order_by, fn {name, _direction} -> name end)

    referenced_names =
      (filter_names ++ order_by_names)
      |> Enum.filter(&(&1 in server_only_names))
      |> Enum.uniq()
      |> Enum.sort()

    nested_references =
      term.include
      |> Map.values()
      |> Enum.flat_map(&server_only_references/1)

    if referenced_names == [] do
      nested_references
    else
      [{term.entity, referenced_names} | nested_references]
    end
  end

  # A registered query is provisioned to the client, which evaluates it locally over rows that
  # never carry a server-only value - so it must not reference one.
  defp validate_client_evaluable_queries!({module, module_terms}) do
    Enum.each(module_terms, fn term ->
      case server_only_references(term) do
        [] ->
          :ok

        references ->
          raise Hologram.CompileError, message: server_only_query_message(module, references)
      end
    end)
  end

  defp validate_readable_includes!(module, term) do
    dead_entity_types =
      term
      |> included_entity_types()
      |> Policy.dead_entity_types()

    if dead_entity_types != [] do
      raise Hologram.CompileError, message: dead_include_message(module, dead_entity_types)
    end

    :ok
  end

  # A registered query naming an entity type with no allow lines is statically dead: the policied
  # read path composes default deny into every statement it reaches. The root and an include target
  # fail differently, so they are checked and reported apart - and a dead root is reported alone,
  # because a query returning no rows produces no embeds to be empty either.
  defp validate_readable_queries!({module, module_terms}) do
    Enum.each(module_terms, fn term ->
      case Policy.dead_entity_types([term.entity]) do
        [] ->
          validate_readable_includes!(module, term)

        dead_entity_types ->
          raise Hologram.CompileError, message: dead_root_message(module, dead_entity_types)
      end
    end)
  end
end
