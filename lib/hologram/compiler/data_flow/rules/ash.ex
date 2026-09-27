defmodule Hologram.Compiler.DataFlow.Rules.Ash do
  @moduledoc false

  # The rules for Ash (see Hologram.Compiler.DataFlow.Rules). Ash builds its records at runtime from
  # what it introspects, so the analysis, following its code, loses track of which records and which
  # types a call gives. These rules answer from the introspection instead: what a value of each type
  # holds (type_shapes/3); the records and the interface functions come on top of it.
  #
  # Hologram compiles without Ash: every call into it is made only when it is loaded (see
  # available?/0).

  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Ash.Resource.Info
  alias Ash.Type.NewType
  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow

  @compile {:no_warn_undefined, [Ash.Resource.Info, Ash.Type, Ash.Type.NewType, Spark]}

  # Ash is not in the Dialyzer PLT either (Hologram does not depend on it).
  @dialyzer {:no_unknown,
             [
               module_tree: 3,
               reachable_resources: 2,
               relationship_fields: 3,
               type_tree: 3,
               value_fields: 2
             ]}

  # Ash's types whose values hold no types: numbers, binaries, atoms (a module name included: a
  # value from storage, not a module the code names) and terms decoded from storage.
  @primitive_types [
    Ash.Type.Atom,
    Ash.Type.Binary,
    Ash.Type.Boolean,
    Ash.Type.DurationName,
    Ash.Type.Float,
    Ash.Type.Function,
    Ash.Type.Integer,
    Ash.Type.Module,
    Ash.Type.String,
    Ash.Type.Term,
    Ash.Type.UUID,
    Ash.Type.UUIDv7,
    Ash.Type.UrlEncodedBinary
  ]

  # Ash's types whose values are structs of the standard library or of Ash, by the struct's module.
  @struct_types %{
    Ash.Type.CiString => Ash.CiString,
    Ash.Type.Date => Date,
    Ash.Type.DateTime => DateTime,
    Ash.Type.Decimal => Decimal,
    Ash.Type.Duration => Duration,
    Ash.Type.NaiveDatetime => NaiveDateTime,
    Ash.Type.Time => Time,
    Ash.Type.TimeUsec => Time,
    Ash.Type.UtcDatetime => DateTime,
    Ash.Type.UtcDatetimeUsec => DateTime
  }

  # The structs of the calendar types, whose calendar field holds the calendar module.
  @calendar_structs [Date, DateTime, NaiveDateTime, Time]

  # How deep records nest through relationships before a related record is a bag of the types every
  # record reachable from it holds, so relationships in a cycle (an item's notes, a note's item) end.
  @record_depth 2

  # The process dictionary key of the resources whose records are being built, so a resource that
  # embeds itself, directly or through another, ends (see record_tree/3).
  @building_key {__MODULE__, :building}

  @doc """
  Returns whether Ash is loaded. Without it no rule of this module applies.
  """
  @spec available?() :: boolean
  def available?, do: Code.ensure_loaded?(Ash.Resource.Info)

  @doc """
  Returns, as a tree, the records of the given Ash resource: its struct, with a field for each
  attribute (its type's shapes, nil or a forbidden field), calculation and aggregate (its type's
  shapes, nil or not loaded) and relationship (the related record, a list of them for a to-many
  relationship, nil or not loaded), and Ash's own fields. Related records nest #{@record_depth} deep,
  then are a bag of the types every record reachable from them holds. Remembered in the flow
  context's rule cache for the compile.
  """
  @spec record_shapes(module, DataFlow.t()) :: DataFlow.tree()
  def record_shapes(resource, flow), do: record_tree(resource, 0, flow)

  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(_part, _modules, _flow), do: []

  @impl Hologram.Compiler.DataFlow.Rules
  def summary(_mfa, _flow), do: nil

  @doc """
  Returns, as a tree, what a value of the given Ash type holds, with the given constraints: a
  primitive for Ash's primitive types; the struct for its calendar, decimal, duration,
  case-insensitive string and money types, each field by what it holds; for a union, a map, a
  keyword list, a tuple and a struct type, their fields by their own types; a new type as its
  subtype; an embedded resource as its record (see `record_shapes/2`). Any other type, one of the app or of another library,
  holds what its `cast_stored/2` gives, followed by the analysis. Remembered in the flow context's
  rule cache for the compile.
  """
  @spec type_shapes(atom | {:array, atom}, keyword, DataFlow.t()) :: DataFlow.tree()
  def type_shapes(type, constraints, flow) do
    cached({__MODULE__, :type, type, constraints}, flow, fn ->
      type_tree(type, constraints, flow)
    end)
  end

  # The tree remembered under the key in the flow context's rule cache, or the function's, remembered.
  defp cached(key, flow, fun) do
    case PLT.get(flow.rule_cache, key) do
      {:ok, tree} ->
        tree

      :error ->
        tree = fun.()
        PLT.put(flow.rule_cache, key, tree)
        tree
    end
  end

  # The fields of a union's members, or of a map, a keyword list, a tuple or a struct type, by name:
  # what each field's type holds.
  defp field_trees(fields, flow) do
    Map.new(fields, fn {name, opts} ->
      {name, type_shapes(opts[:type], Keyword.get(opts, :constraints, []), flow)}
    end)
  end

  defp fields_leaves(fields) do
    fields
    |> Map.values()
    |> Enum.flat_map(&tree_leaves/1)
  end

  # A record's field that Ash can leave not loaded: the field's shapes, nil, or `Ash.NotLoaded`, which
  # names the resource.
  defp loadable(tree, resource), do: union([tree, [:prim], not_loaded(resource)])

  defp map_tree(constraints, flow) do
    case constraints[:fields] do
      nil -> [{:map, DataFlow.rest_fields([:prim])}]
      fields -> [{:map, field_trees(fields, flow)}]
    end
  end

  defp module_tree(type, _constraints, _flow) when type in @primitive_types, do: [:prim]

  defp module_tree(type, _constraints, _flow) when is_map_key(@struct_types, type) do
    struct = Map.fetch!(@struct_types, type)

    if struct in @calendar_structs do
      struct_tree(struct, %{calendar: [{:atom, Calendar.ISO}]})
    else
      struct_tree(struct, %{})
    end
  end

  defp module_tree(AshMoney.Types.Money, _constraints, _flow) do
    struct_tree(Money, %{amount: struct_tree(Decimal, %{})})
  end

  defp module_tree(Ash.Type.Union, constraints, flow) do
    members =
      constraints
      |> Keyword.get(:types, [])
      |> field_trees(flow)
      |> Map.values()
      |> Enum.concat()
      |> :lists.usort()

    struct_tree(Ash.Union, %{value: members})
  end

  defp module_tree(Ash.Type.Struct, constraints, flow) do
    case constraints[:instance_of] do
      nil -> map_tree(constraints, flow)
      struct -> struct_tree(struct, field_trees(Keyword.get(constraints, :fields, []), flow))
    end
  end

  defp module_tree(Ash.Type.Map, constraints, flow), do: map_tree(constraints, flow)

  defp module_tree(Ash.Type.Keyword, constraints, flow) do
    values =
      case constraints[:fields] do
        nil ->
          [:prim]

        fields ->
          fields
          |> field_trees(flow)
          |> Map.values()
          |> Enum.concat()
          |> :lists.usort()
      end

    [{:list, [{:tuple, [[:prim], values]}]}]
  end

  defp module_tree(Ash.Type.Tuple, constraints, flow) do
    case constraints[:fields] do
      nil ->
        [:prim]

      fields ->
        trees = field_trees(fields, flow)
        [{:tuple, Enum.map(fields, fn {name, _opts} -> Map.fetch!(trees, name) end)}]
    end
  end

  defp module_tree(type, constraints, flow) do
    cond do
      NewType.new_type?(type) ->
        constraints = Keyword.merge(type.subtype_constraints(), constraints)

        type
        |> NewType.subtype_of()
        |> type_shapes(NewType.constraints(type, constraints), flow)

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        [:prim]

      Info.resource?(type) ->
        record_tree(type, 0, flow)

      true ->
        [{:contents, [{:dyn, [{:atom, type}], :cast_stored, 2, [[:prim], [:prim]]}]}]
    end
  end

  defp not_loaded(resource), do: struct_tree(Ash.NotLoaded, %{resource: [{:atom, resource}]})

  # The types every record reachable from the resource holds, as leaves: each reachable resource's
  # struct and what its attributes, calculations and aggregates hold.
  defp reachable_leaves(resource, flow) do
    cached({__MODULE__, :reachable, resource}, flow, fn ->
      [resource]
      |> reachable_resources(%{})
      |> Enum.flat_map(fn reachable ->
        leaves =
          reachable
          |> value_fields(flow)
          |> Map.values()
          |> Enum.flat_map(&tree_leaves/1)

        [{:struct, reachable, %{}} | leaves]
      end)
      |> :lists.usort()
    end)
  end

  # The resources the given ones reach through relationships, themselves included.
  defp reachable_resources([], visited), do: Map.keys(visited)

  defp reachable_resources([resource | resources], visited) do
    if Map.has_key?(visited, resource) do
      reachable_resources(resources, visited)
    else
      destinations =
        resource
        |> Info.relationships()
        |> Enum.map(& &1.destination)

      reachable_resources(destinations ++ resources, Map.put(visited, resource, true))
    end
  end

  # The record of the resource, its relationships nested to the given depth (see @record_depth). A
  # resource already being built (an embedded resource holding itself) is its struct and the rule
  # before the analysis applied from its module, which covers what its records hold.
  defp record_tree(resource, depth, flow) do
    building = Process.get(@building_key, %{})

    if Map.has_key?(building, resource) do
      [{:bag, [{:reach, resource}, {:struct, resource, %{}}]}]
    else
      cached({__MODULE__, :record, resource, depth}, flow, fn ->
        Process.put(@building_key, Map.put(building, resource, true))

        try do
          fields =
            resource
            |> value_fields(flow)
            |> Map.merge(relationship_fields(resource, depth, flow))
            |> Map.merge(status_fields(resource, flow))

          [{:struct, resource, fields}]
        after
          Process.put(@building_key, building)
        end
      end)
    end
  end

  # A record's relationships: the related record, a list of them for a to-many relationship, below
  # @record_depth a bag of the types every record reachable from it holds; nil or not loaded.
  defp relationship_fields(resource, depth, flow) do
    resource
    |> Info.relationships()
    |> Map.new(fn relationship ->
      related =
        if depth + 1 < @record_depth do
          record_tree(relationship.destination, depth + 1, flow)
        else
          [{:bag, reachable_leaves(relationship.destination, flow)}]
        end

      related = if relationship.cardinality == :many, do: [{:list, related}], else: related

      {relationship.name, loadable(related, resource)}
    end)
  end

  # Ash's own fields of a record: the Ecto metadata (naming the resource), the metadata map, the
  # maps of calculations and aggregates loaded under other names, and two primitives.
  defp status_fields(resource, flow) do
    loaded =
      resource
      |> value_fields(flow)
      |> Map.values()
      |> union()

    loaded_rest =
      [[:prim], loaded]
      |> union()
      |> DataFlow.rest_fields()

    %{
      __lateral_join_source__: [:prim],
      __meta__: struct_tree(Ecto.Schema.Metadata, %{schema: [{:atom, resource}]}),
      __metadata__: [{:map, DataFlow.rest_fields([:prim])}],
      __order__: [:prim],
      aggregates: [{:map, loaded_rest}],
      calculations: [{:map, loaded_rest}]
    }
  end

  # The struct of the module with the given fields' trees, every other field of it a primitive; with
  # the struct not loaded, its other fields are not known and are a rest of primitives.
  defp struct_tree(module, overrides) do
    fields =
      if Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0) do
        module.__struct__()
        |> Map.delete(:__struct__)
        |> Map.new(fn {key, _default} -> {key, Map.get(overrides, key, [:prim])} end)
      else
        [:prim]
        |> DataFlow.rest_fields()
        |> Map.merge(overrides)
      end

    [{:struct, module, fields}]
  end

  # A tree's shapes flattened: a struct with no fields, and what every nested tree holds.
  defp tree_leaves(tree) do
    Enum.flat_map(tree, fn
      {:struct, module, fields} -> [{:struct, module, %{}} | fields_leaves(fields)]
      {:map, fields} -> fields_leaves(fields)
      {:tuple, elements} -> Enum.flat_map(elements, &tree_leaves/1)
      {kind, inner} when kind in [:bag, :list] -> tree_leaves(inner)
      shape -> [shape]
    end)
  end

  defp type_tree({:array, type}, constraints, flow) do
    [{:list, type_shapes(type, Keyword.get(constraints, :items, []), flow)}]
  end

  defp type_tree(type, constraints, flow) do
    type
    |> Ash.Type.get_type()
    |> module_tree(constraints, flow)
  end

  # The given trees as one, sorted, each shape once (the analysis merges the shapes of a kind when it
  # interns the tree).
  defp union(trees) do
    trees
    |> Enum.concat()
    |> :lists.usort()
  end

  # A record's attributes, calculations and aggregates: each type's shapes and nil; an attribute can
  # also be a forbidden field, which may hold its original value, and a calculation or an aggregate not
  # loaded.
  defp value_fields(resource, flow) do
    attributes =
      resource
      |> Info.attributes()
      |> Map.new(fn attribute ->
        tree = type_shapes(attribute.type, attribute.constraints || [], flow)
        forbidden = struct_tree(Ash.ForbiddenField, %{original_value: union([tree, [:prim]])})
        {attribute.name, union([tree, [:prim], forbidden])}
      end)

    calculations =
      resource
      |> Info.calculations()
      |> Map.new(fn calculation ->
        tree = type_shapes(calculation.type, calculation.constraints || [], flow)
        {calculation.name, loadable(tree, resource)}
      end)

    aggregates =
      resource
      |> Info.aggregates()
      |> Map.new(fn aggregate ->
        {:ok, type} = Info.aggregate_type(resource, aggregate)
        tree = type_shapes(type, aggregate.constraints || [], flow)
        {aggregate.name, loadable(tree, resource)}
      end)

    attributes
    |> Map.merge(calculations)
    |> Map.merge(aggregates)
  end
end
