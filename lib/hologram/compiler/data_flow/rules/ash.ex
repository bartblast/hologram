defmodule Hologram.Compiler.DataFlow.Rules.Ash do
  @moduledoc false

  # The rules for the data framework (see Hologram.Compiler.DataFlow.Rules). The framework builds
  # its records at runtime from what it introspects, so the analysis, following its code, loses
  # track of which records and which types a call gives. These rules answer from the introspection
  # instead: what a value of each type holds (type_shapes/3); the records and the interface
  # functions come on top of it.
  #
  # Hologram compiles without the framework: every call into it is made only when it is loaded (see
  # available?/0).

  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Ash.Resource.Info
  alias Ash.Type.NewType
  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow

  @compile {:no_warn_undefined, [Ash.Resource.Info, Ash.Type, Ash.Type.NewType, Spark]}

  # The framework is not in the Dialyzer PLT either (Hologram does not depend on it).
  @dialyzer {:no_unknown, [module_tree: 3, type_tree: 3]}

  # The framework's types whose values hold no types: numbers, binaries, atoms (a module name
  # included: a value from storage, not a module the code names) and terms decoded from storage.
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

  # The framework's types whose values are structs of the standard library or of the framework, by
  # the struct's module.
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

  @doc """
  Returns whether the data framework is loaded. Without it no rule of this module applies.
  """
  @spec available?() :: boolean
  def available?, do: Code.ensure_loaded?(Ash.Resource.Info)

  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(_part, _modules, _flow), do: []

  @impl Hologram.Compiler.DataFlow.Rules
  def summary(_mfa, _flow), do: nil

  @doc """
  Returns, as a tree, what a value of the given type of the data framework holds, with the given
  constraints: a primitive for the framework's primitive types; the struct for its calendar, decimal,
  duration, case-insensitive string and money types, each field by what it holds; for a union, a map,
  a keyword list, a tuple and a struct type, their fields by their own types; a new type as its
  subtype; an embedded resource as its struct. Any other type, one of the app or of another library,
  holds what its `cast_stored/2` gives, followed by the analysis. Remembered in the flow context's
  rule cache for the compile.
  """
  @spec type_shapes(atom | {:array, atom}, keyword, DataFlow.t()) :: DataFlow.tree()
  def type_shapes(type, constraints, flow) do
    key = {__MODULE__, :type, type, constraints}

    case PLT.get(flow.rule_cache, key) do
      {:ok, tree} ->
        tree

      :error ->
        tree = type_tree(type, constraints, flow)
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
        [{:struct, type, %{}}]

      true ->
        [{:contents, [{:dyn, [{:atom, type}], :cast_stored, 2, [[:prim], [:prim]]}]}]
    end
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

  defp type_tree({:array, type}, constraints, flow) do
    [{:list, type_shapes(type, Keyword.get(constraints, :items, []), flow)}]
  end

  defp type_tree(type, constraints, flow) do
    type
    |> Ash.Type.get_type()
    |> module_tree(constraints, flow)
  end
end
