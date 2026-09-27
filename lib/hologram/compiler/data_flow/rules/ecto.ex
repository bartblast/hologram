defmodule Hologram.Compiler.DataFlow.Rules.Ecto do
  @moduledoc false

  # The rules for Ecto (see Hologram.Compiler.DataFlow.Rules). Ecto builds a schema's records at
  # runtime from what it loads, each field by its type, so the analysis, following its code, loses
  # track of which types a record's fields hold. These rules answer from the schema's reflection
  # instead: what a value of each Ecto type holds (type_shapes/2), a schema's records
  # (record_shapes/2), and what a repo's functions give (summary/2).
  #
  # A schema whose records another rules module knows (an Ash resource is an Ecto schema too) has
  # those records wherever these rules need one (see Rules.record/2), so a record has one answer
  # however it was loaded. These rules do not answer that question themselves: their records nest by
  # depth, which the question does not carry.
  #
  # Hologram compiles without Ecto: the rules call only the reflection functions a schema defines.

  @behaviour Hologram.Compiler.DataFlow.Rules

  import Hologram.Compiler.DataFlow.Rules.Trees

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules
  alias Hologram.Reflection

  # Ecto's types whose values hold no types: numbers, binaries, booleans, ids, maps decoded from
  # storage, strings and any term.
  @primitive_types [
    :any,
    :binary,
    :binary_id,
    :bitstring,
    :boolean,
    :float,
    :id,
    :integer,
    :map,
    :string
  ]

  # Ecto's types whose values are structs of the standard library or of a library, by the struct's
  # module.
  @struct_types %{
    date: Date,
    decimal: Decimal,
    duration: Duration,
    naive_datetime: NaiveDateTime,
    naive_datetime_usec: NaiveDateTime,
    time: Time,
    time_usec: Time,
    utc_datetime: DateTime,
    utc_datetime_usec: DateTime
  }

  # A repo's functions by what they give (see repo_tree/1): a list of records, what they are given
  # reloaded or with its associations loaded, one record, one record or nil, and `{:ok, record}` or
  # `{:error, changeset}`.
  @repo_lists [:all, :all_by]
  @repo_loads [:preload, :reload!]
  @repo_ones [:delete!, :get!, :get_by!, :insert!, :insert_or_update!, :one!, :update!]
  @repo_optional_ones [:get, :get_by, :one]
  @repo_writes [:delete, :insert, :insert_or_update, :update]

  # What a repo function's rule shapes read the schemas from: its first argument (a schema module, a
  # record, a list of them, a changeset) and what is inside it (a list's records, a changeset's
  # data).
  @repo_subject [{:param, 0}, {:contents, [{:param, 0}]}]

  # How deep records nest through associations before a related record is a bag of the types every
  # record reachable from it holds, so associations in a cycle (a post's comments, a comment's post)
  # end.
  @record_depth 2

  # The process dictionary key of the schemas whose records are being built, so a schema that
  # embeds itself, directly or through another, ends (see type_tree/2).
  @building_key {__MODULE__, :building}

  @doc """
  Returns, as a tree, the records of the given Ecto schema: its struct, with a field for each field
  and virtual field (its type's shapes or nil; an embed's record, a list of them for `embeds_many`)
  and association (the related record, a list of them for a to-many association, nil or not
  loaded), and the metadata of a schema with a source. Related records nest #{@record_depth} deep,
  then are a bag of the types every record reachable from them holds; a related schema whose records
  another rules module knows has those (see `Hologram.Compiler.DataFlow.Rules.record/2`).
  Remembered in the flow context's rule cache for the compile.
  """
  @spec record_shapes(module, DataFlow.t()) :: DataFlow.tree()
  def record_shapes(schema, flow), do: record_tree(schema, 0, flow)

  @doc """
  Returns what a rule shape of this module (see `summary/2`) gives once the atoms and struct modules
  among its arguments are known: `:records`, the records of the schemas among them (every schema's,
  as a bag of the types they hold, when there is none); `:changeset`, a changeset holding them.
  """
  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(:records, [modules], flow), do: records_of(modules, flow)

  def resolve(:changeset, [modules], flow) do
    records = records_of(modules, flow)

    # A change holds a field's value: a primitive, a record's types, or a nested changeset.
    changes =
      [[:prim], [{:bag, [{:struct, Ecto.Changeset, %{}} | tree_leaves(records)]}]]
      |> union()
      |> DataFlow.rest_fields()

    struct_tree(Ecto.Changeset, %{changes: [{:map, changes}], data: records})
  end

  @doc """
  Returns what a repo's function (of a module defining `__adapter__/0`) gives: the records of the
  schemas its first argument names (a schema module, a record, a list of them, a changeset), a list
  of them, one, or one or nil, as the function gives them; `{:ok, record}` or `{:error, changeset}`
  for the writes that do not raise; what it is given, reloaded or with its associations loaded, for
  `preload/3` and `reload/2`. Nil for a repo's other functions and for any other module's.
  """
  @impl Hologram.Compiler.DataFlow.Rules
  def summary({module, function, _arity}, flow) do
    if repo?(module, flow), do: repo_tree(function)
  end

  @doc """
  Returns, as a tree, what a value of the given Ecto type holds: a primitive for Ecto's primitive
  types and `Ecto.Enum`; the struct for its calendar, decimal and duration types; a list or a map of
  the inner type's values; an embedded schema's record, or a list of them. Any other type, one of
  the app or of another library, holds what its `load/1` (`load/3` for a parameterized type) gives,
  followed by the analysis. Remembered in the flow context's rule cache for the compile.
  """
  @spec type_shapes(term, DataFlow.t()) :: DataFlow.tree()
  def type_shapes(type, flow) do
    cached({__MODULE__, :type, type}, flow, fn -> type_tree(type, flow) end)
  end

  # Every schema's records, as a bag of the types they hold: what a call gives when nothing in its
  # arguments names a schema.
  defp all_records(flow) do
    cached({__MODULE__, :all_records}, flow, fn ->
      leaves =
        flow
        |> schemas()
        |> Enum.flat_map(&reachable_leaves(&1, flow))
        |> :lists.usort()

      [{:bag, leaves}]
    end)
  end

  # A record's associations: the related record (the one another rules module knows, see
  # Rules.record/2), a list of them for a to-many association, below @record_depth a bag of the
  # types every record reachable from it holds; nil or not loaded.
  defp association_fields(schema, depth, flow) do
    :associations
    |> schema.__schema__()
    |> Map.new(fn name ->
      association = schema.__schema__(:association, name)
      related_schema = related(schema, association)

      related =
        cond do
          known = Rules.record(related_schema, flow) -> known
          depth + 1 < @record_depth -> record_tree(related_schema, depth + 1, flow)
          true -> [{:bag, reachable_leaves(related_schema, flow)}]
        end

      related = if association.cardinality == :many, do: [{:list, related}], else: related
      not_loaded = struct_tree(Ecto.Association.NotLoaded, %{__owner__: [{:atom, schema}]})

      {name, union([related, [:prim], not_loaded])}
    end)
  end

  # The metadata of a schema with a source, naming the schema; an embedded schema has none.
  defp meta_fields(schema) do
    if Map.has_key?(schema.__struct__(), :__meta__) do
      %{__meta__: struct_tree(Ecto.Schema.Metadata, %{schema: [{:atom, schema}]})}
    else
      %{}
    end
  end

  # The types every record reachable from the schema holds, as leaves (see record_leaves/2).
  defp reachable_leaves(schema, flow) do
    cached({__MODULE__, :reachable, schema}, flow, fn ->
      [schema]
      |> reachable_schemas(%{}, flow)
      |> Enum.flat_map(&record_leaves(&1, flow))
      |> :lists.usort()
    end)
  end

  # The schemas the given ones reach through associations, themselves included; the associations of
  # a schema whose records another rules module knows are not walked (see reachable_leaves/2).
  defp reachable_schemas([], visited, _flow), do: Map.keys(visited)

  defp reachable_schemas([schema | schemas], visited, flow) do
    cond do
      Map.has_key?(visited, schema) ->
        reachable_schemas(schemas, visited, flow)

      Rules.record(schema, flow) ->
        reachable_schemas(schemas, Map.put(visited, schema, true), flow)

      true ->
        related =
          :associations
          |> schema.__schema__()
          |> Enum.map(&related(schema, schema.__schema__(:association, &1)))

        reachable_schemas(related ++ schemas, Map.put(visited, schema, true), flow)
    end
  end

  # The types a record of the schema holds, as leaves: its struct and what its fields hold; for a
  # schema whose records another rules module knows, the leaves of that record, which holds its
  # related records itself.
  defp record_leaves(schema, flow) do
    case Rules.record(schema, flow) do
      nil -> [{:struct, schema, %{}} | value_leaves(schema, flow)]
      known -> tree_leaves(known)
    end
  end

  # The record of the schema, its associations nested to the given depth (see @record_depth), which
  # ends them; the schema is marked as being built meanwhile, which ends embeds (see type_tree/2).
  defp record_tree(schema, depth, flow) do
    cached({__MODULE__, :record, schema, depth}, flow, fn ->
      building = Process.get(@building_key, %{})
      Process.put(@building_key, Map.put(building, schema, true))

      try do
        fields =
          schema
          |> value_fields(flow)
          |> Map.merge(association_fields(schema, depth, flow))
          |> Map.merge(meta_fields(schema))

        [{:struct, schema, fields}]
      after
        Process.put(@building_key, building)
      end
    end)
  end

  # The rule shape of the records of the schemas a repo function's first argument names.
  defp records, do: [{:rule, __MODULE__, :records, [@repo_subject]}]

  # The records of the schemas among the modules, each the one another rules module knows or these
  # rules' own (see Rules.record/2); every schema's when there is none.
  defp records_of(modules, flow) do
    case Enum.filter(modules, &Reflection.ecto_schema?/1) do
      [] ->
        all_records(flow)

      schemas ->
        schemas
        |> Enum.map(&(Rules.record(&1, flow) || record_shapes(&1, flow)))
        |> union()
    end
  end

  # The schema an association gives records of: its related schema, or for an association through
  # others, the one the last of them gives.
  defp related(schema, %{through: [name | names]}) do
    related = related(schema, schema.__schema__(:association, name))

    case names do
      [] -> related
      _more -> related(related, %{through: names})
    end
  end

  defp related(_schema, %{related: related}), do: related

  # Whether the module is a repo (it defines `__adapter__/0`), asked once per module and compile.
  defp repo?(module, flow) do
    cached({__MODULE__, :repo?, module}, flow, fn ->
      Reflection.has_function?(module, :__adapter__, 0)
    end)
  end

  # What a repo's function gives (see summary/2), or nil for one these rules do not answer.
  defp repo_tree(function) when function in @repo_lists, do: [{:list, records()}]

  defp repo_tree(function) when function in @repo_loads, do: union([[{:param, 0}], records()])

  defp repo_tree(:reload), do: union([[{:param, 0}, :prim], records()])

  defp repo_tree(function) when function in @repo_ones, do: records()

  defp repo_tree(function) when function in @repo_optional_ones, do: union([records(), [:prim]])

  defp repo_tree(function) when function in @repo_writes do
    changeset = [{:rule, __MODULE__, :changeset, [@repo_subject]}]
    [{:tuple, [[{:atom, :ok}], records()]}, {:tuple, [[{:atom, :error}], changeset]}]
  end

  defp repo_tree(_function), do: nil

  # The schemas among the compile's modules, by the module info's flag.
  defp schemas(flow) do
    cached({__MODULE__, :schemas}, flow, fn ->
      for {module, %{ecto_schema?: true}} <- PLT.get_all(flow.module_info_plt), do: module
    end)
  end

  defp type_tree(type, _flow) when type in @primitive_types, do: [:prim]

  defp type_tree(type, _flow) when is_map_key(@struct_types, type),
    do: value_struct_tree(Map.fetch!(@struct_types, type))

  defp type_tree({:array, type}, flow), do: [{:list, type_shapes(type, flow)}]

  defp type_tree({:map, type}, flow) do
    values = union([[:prim], type_shapes(type, flow)])
    [{:map, DataFlow.rest_fields(values)}]
  end

  # A parameterized type as Ecto before 3.12 writes it.
  defp type_tree({:parameterized, module, params}, flow),
    do: type_tree({:parameterized, {module, params}}, flow)

  defp type_tree({:parameterized, {Ecto.Enum, _params}}, _flow), do: [:prim]

  # An embedded schema's record; one already being built (a schema embedding itself, directly or
  # through another) is its struct and the rule before the analysis applied from its module, which
  # covers what its records hold.
  defp type_tree({:parameterized, {Ecto.Embedded, embedded}}, flow) do
    building = Process.get(@building_key, %{})
    related = embedded.related

    record =
      if Map.has_key?(building, related) do
        [{:bag, [{:reach, related}, {:struct, related, %{}}]}]
      else
        record_tree(related, 0, flow)
      end

    if embedded.cardinality == :many, do: [{:list, record}], else: record
  end

  defp type_tree({:parameterized, {module, _params}}, _flow),
    do: [{:contents, [{:dyn, [{:atom, module}], :load, 3, [[:prim], [:prim], [:prim]]}]}]

  defp type_tree(module, _flow) when is_atom(module),
    do: [{:contents, [{:dyn, [{:atom, module}], :load, 1, [[:prim]]}]}]

  # A record's fields and virtual fields: each type's shapes and nil.
  defp value_fields(schema, flow) do
    fields =
      :fields
      |> schema.__schema__()
      |> Map.new(&{&1, schema.__schema__(:type, &1)})

    virtual_fields =
      :virtual_fields
      |> schema.__schema__()
      |> Map.new(&{&1, schema.__schema__(:virtual_type, &1)})

    fields
    |> Map.merge(virtual_fields)
    |> Map.new(fn {field, type} -> {field, union([type_shapes(type, flow), [:prim]])} end)
  end

  # What a record's fields hold, as leaves (see value_fields/2).
  defp value_leaves(schema, flow) do
    schema
    |> value_fields(flow)
    |> Map.values()
    |> Enum.flat_map(&tree_leaves/1)
  end
end
