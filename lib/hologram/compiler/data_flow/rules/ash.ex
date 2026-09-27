defmodule Hologram.Compiler.DataFlow.Rules.Ash do
  @moduledoc false

  # The rules for Ash (see Hologram.Compiler.DataFlow.Rules). Ash builds its records at runtime from
  # what it introspects, so the analysis, following its code, loses track of which records and which
  # types a call gives. These rules answer from the introspection instead: what a value of each type
  # holds (type_shapes/3), a resource's records (record_shapes/2), and what the functions Ash
  # generates from a resource's or a domain's code interface give (summary/2).
  #
  # Hologram compiles without Ash: every call into it is made only when it is loaded (see
  # available?/0).

  @behaviour Hologram.Compiler.DataFlow.Rules

  alias Ash.Domain.Info, as: DomainInfo
  alias Ash.Resource.Info
  alias Ash.Type.NewType
  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Reflection
  alias Spark.Dsl.Extension

  @compile {:no_warn_undefined,
            [
              Ash.Domain.Info,
              Ash.Resource.Info,
              Ash.Type,
              Ash.Type.NewType,
              Spark,
              Spark.Dsl,
              Spark.Dsl.Extension
            ]}

  # Ash is not in the Dialyzer PLT either (Hologram does not depend on it).
  @dialyzer {:no_unknown,
             [
               action_tree: 3,
               calculation_tree: 3,
               domain_entries: 1,
               interface_action: 2,
               interface_names: 2,
               interface_tree: 4,
               module_entries: 1,
               module_tree: 3,
               resource_entries: 1,
               resources: 1,
               resources_among: 1,
               subject_module: 2,
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

  # Ash's functions by what they give (see api_tree/1): a list of records, one record or nil, the
  # record a create or an update gives, a destroy's, the records given back loaded, what an action
  # or a calculation gives, a bulk result, and primitives.
  @api_bulk [:bulk_create, :bulk_destroy, :bulk_update]
  @api_destroys [:destroy, :destroy!]
  @api_lists [:read, :read!]
  @api_loads [:load, :load!]
  @api_ones [:get, :get!, :read_one, :read_one!]
  @api_primitives [:aggregate, :aggregate!, :count, :count!, :exists, :exists?]
  @api_runs [:calculate, :calculate!, :run_action, :run_action!]
  @api_writes [:create, :create!, :update, :update!]

  # Ash's error classes, which an interface function's `{:error, error}` holds.
  @error_classes [Ash.Error.Forbidden, Ash.Error.Framework, Ash.Error.Invalid, Ash.Error.Unknown]

  # The prefixes of the modules of Ash and its extensions whose functions no rule answers: the
  # analysis does not follow them (see opaque?/2).
  @opaque_prefixes ["Elixir.Ash.", "Elixir.AshMoney.", "Elixir.AshPostgres.", "Elixir.Spark."]

  # The modules whose functions build a query, a changeset or an action input.
  @subjects [Ash.ActionInput, Ash.Changeset, Ash.Query]

  # How deep records nest through relationships before a related record is a bag of the types every
  # record reachable from it holds, so relationships in a cycle (an item's notes, a note's item)
  # end.
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
  relationship, nil or not loaded), and Ash's own fields. Related records nest #{@record_depth}
  deep, then are a bag of the types every record reachable from them holds. Remembered in the flow
  context's rule cache for the compile.
  """
  @spec record_shapes(module, DataFlow.t()) :: DataFlow.tree()
  def record_shapes(resource, flow), do: record_tree(resource, 0, flow)

  @doc """
  Returns what a rule shape of this module (see `summary/2`) gives once the atoms and struct modules
  among its arguments are known: `:records`, the records of the resources among them (every
  resource's, as a bag of their types, when there is none); `:errors`, the errors of those
  resources; `:subject`, a query, a changeset or an action input (the module the first argument
  names) holding those resources and their records.
  """
  @impl Hologram.Compiler.DataFlow.Rules
  def resolve(:records, [modules], flow), do: records_of(modules, flow)

  def resolve(:errors, [modules], flow) do
    case resources_among(modules) do
      [] ->
        error_tree(nil, flow)

      resources ->
        resources
        |> Enum.map(&error_tree(&1, flow))
        |> union()
    end
  end

  def resolve(:subject, [[module], modules], flow) do
    atoms =
      modules
      |> resources_among()
      |> Enum.map(&{:atom, &1})

    rest = union([[:prim], atoms, records_of(modules, flow)])
    [{:struct, module, DataFlow.rest_fields(rest)}]
  end

  @doc """
  Returns what a function Ash generates from a resource's or a domain's code interface gives (its
  `define` and `define_calculation`, in every form: `name`, `name!`, `can_name`, `can_name?` and
  `query_to_name`, `changeset_to_name` or `input_to_name`), by the interface's action: the records
  of a read, a list of them or a page, the record a create or an update gives, and so on, `{:ok,
  ...}` or `{:error, error}` for the forms that do not raise. Ash's own functions (`Ash.read!/2`,
  `Ash.get/3`, `Ash.update!/3` and the like) give a rule shape over the argument that names the
  resource (a resource, a query, a changeset or a record, never the options: an `actor:` there must
  not bring its records in), wrapped the same way; `Ash.count/2` and the like a primitive. A
  function of `Ash.Query`, `Ash.Changeset` or `Ash.ActionInput` gives that struct, holding the
  resources and the records of its first argument (see `resolve/3`). A function of Ash's or its
  extensions' modules that none of these answers gives its top: the analysis does not follow the
  framework's internals. Nil for any other function, or without Ash.
  """
  @impl Hologram.Compiler.DataFlow.Rules
  def summary({module, function, arity}, flow) do
    if loaded?(flow), do: loaded_summary(module, function, arity, flow)
  end

  @doc """
  Returns, as a tree, what a value of the given Ash type holds, with the given constraints: a
  primitive for Ash's primitive types; the struct for its calendar, decimal, duration,
  case-insensitive string and money types, each field by what it holds; for a union, a map, a
  keyword list, a tuple and a struct type, their fields by their own types; a new type as its
  subtype; an embedded resource as its record (see `record_shapes/2`). Any other type, one of the
  app or of another library, holds what its `cast_stored/2` gives, followed by the analysis.
  Remembered in the flow context's rule cache for the compile.
  """
  @spec type_shapes(atom | {:array, atom}, keyword, DataFlow.t()) :: DataFlow.tree()
  def type_shapes(type, constraints, flow) do
    cached({__MODULE__, :type, type, constraints}, flow, fn ->
      type_tree(type, constraints, flow)
    end)
  end

  # What running the action gives, as the forms that raise give it: a read's record or nil when it
  # gets one, else a list of records or, when it paginates, a page of them; a create's or an
  # update's record, with its notifications when asked for them; a destroy's `:ok` or the destroyed
  # record; a generic action's return type, or `:ok` without one.
  defp action_tree(resource, interface, flow) do
    action = interface_action(resource, interface)
    record = record_shapes(resource, flow)

    case action.type do
      :read ->
        read_tree(record, interface, action)

      type when type in [:create, :update] ->
        union([record, notified([{:atom, resource}], record)])

      :destroy ->
        union([[{:atom, :ok}], record, notified([{:atom, resource}], record)])

      :action ->
        returns_tree(action, flow)
    end
  end

  # Every resource's records, as a bag of the types they hold: what a call gives when nothing in its
  # arguments names a resource.
  defp all_records(flow) do
    cached({__MODULE__, :all_records}, flow, fn ->
      leaves =
        flow
        |> resources()
        |> Enum.flat_map(&reachable_leaves(&1, flow))
        |> :lists.usort()

      [{:bag, leaves}]
    end)
  end

  # What Ash's function gives before it is wrapped (see api_tree/1).
  defp api_result(function, records, _errors) when function in @api_lists,
    do: paged([{:list, records}])

  defp api_result(function, records, _errors) when function in @api_ones,
    do: union([records, [:prim]])

  defp api_result(function, records, _errors) when function in @api_writes,
    do: union([records, notified([:prim], records)])

  defp api_result(function, records, _errors) when function in @api_destroys,
    do: union([[{:atom, :ok}], records, notified([:prim], records)])

  defp api_result(function, records, _errors) when function in @api_loads,
    do: union([records, [{:list, records}]])

  defp api_result(function, records, _errors) when function in @api_runs,
    do: union([[:prim], records])

  defp api_result(function, records, errors) when function in @api_bulk do
    struct_tree(Ash.BulkResult, %{
      errors: union([[:prim], [{:list, errors}]]),
      records: union([[:prim], [{:list, records}]])
    })
  end

  defp api_result(:stream!, records, _errors),
    do: [{:struct, Stream, DataFlow.rest_fields(records)}]

  defp api_result(function, _records, _errors) when function in @api_primitives, do: [:prim]

  defp api_result(_function, _records, _errors), do: nil

  # What Ash's function gives (see summary/2), over a rule shape of the records of the resource its
  # subject argument names (param 1 of `bulk_create`, whose first is its inputs; param 0 of the
  # others), the forms that do not raise wrapped with the errors of those resources; nil for another
  # function.
  defp api_tree(function) do
    subject = if function == :bulk_create, do: 1, else: 0
    records = [{:rule, __MODULE__, :records, [[{:param, subject}]]}]
    errors = [{:rule, __MODULE__, :errors, [[{:param, subject}]]}]

    function
    |> api_result(records, errors)
    |> api_wrapped(function, errors)
  end

  # The result as the function gives it: as it is for the forms that raise (a name ending in `!` or
  # `?`) and for the bulk ones, else `{:ok, result}` or `{:error, error}`, and `:ok` for a destroy
  # or an action.
  defp api_wrapped(nil, _function, _errors), do: nil

  defp api_wrapped(result, function, errors) do
    name = Atom.to_string(function)

    cond do
      String.ends_with?(name, ["!", "?"]) or function in @api_bulk ->
        result

      function in [:destroy, :run_action] ->
        union([[{:atom, :ok}], wrapped_with(result, errors)])

      true ->
        wrapped_with(result, errors)
    end
  end

  # Whether the module is one of Ash's exceptions, by its name.
  defp ash_exception?(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.Ash.Error.")
  end

  # What a calculation interface's calculation gives: its type's shapes.
  defp calculation_tree(resource, interface, flow) do
    calculation = Info.calculation(resource, interface.calculation)
    type_shapes(calculation.type, calculation.constraints || [], flow)
  end

  # The tree remembered under the key in the flow context's rule cache, or the function's,
  # remembered.
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

  # The functions a domain's code interface generates: its definitions for each of its resources, on
  # the domain or on its namespace module (see interface_entries/3).
  defp domain_entries(domain) do
    for reference <- DomainInfo.resource_references(domain),
        interface <- reference.definitions,
        entry <- interface_entries(domain, reference.resource, interface, reference.namespace),
        do: entry
  end

  # What `{:error, error}` holds: each of Ash's error classes, its errors a list of Ash's
  # exceptions, its changeset, query or action input one of the resource's (see subject_tree/3), nil
  # or not.
  defp error_tree(resource, flow) do
    cached({__MODULE__, :error, resource}, flow, fn ->
      exceptions =
        flow
        |> exceptions()
        |> Enum.map(&{:struct, &1, DataFlow.rest_fields([:prim])})

      @error_classes
      |> Enum.map(fn class ->
        struct_tree(class, %{
          action_input: union([[:prim], subject_tree(Ash.ActionInput, resource, flow)]),
          changeset: union([[:prim], subject_tree(Ash.Changeset, resource, flow)]),
          errors: [{:list, exceptions}],
          query: union([[:prim], subject_tree(Ash.Query, resource, flow)])
        })
      end)
      |> union()
    end)
  end

  # Ash's exceptions among the compile's modules (the module info's `exception?` flag), which an
  # error class can hold.
  defp exceptions(flow) do
    cached({__MODULE__, :exceptions}, flow, fn ->
      modules =
        for {module, %{exception?: true}} <- PLT.get_all(flow.module_info_plt),
            ash_exception?(module),
            do: module

      Enum.sort(modules)
    end)
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

  # The action an interface runs: the one it names, or the one of its own name.
  defp interface_action(resource, interface),
    do: Info.action(resource, interface.action || interface.name)

  # The functions an interface generates, each keyed by the module it is generated on (the host, or
  # the host's namespace module) and its name as a string, with the resource, the interface and the
  # form. A name ending in `?` is the form that raises, as Ash names it.
  defp interface_entries(host, resource, interface, default_namespace) do
    case interface_module(host, Map.get(interface, :namespace) || default_namespace) do
      nil ->
        []

      module ->
        interface
        |> interface_names(resource)
        |> Enum.map(fn {function, form} -> {{module, function}, {resource, interface, form}} end)
    end
  end

  # The functions of every resource's and domain's code interface in the compile, by module and
  # name.
  defp interface_index(flow) do
    cached({__MODULE__, :interfaces}, flow, fn ->
      flow.module_info_plt
      |> PLT.get_all()
      |> Map.keys()
      |> Enum.flat_map(&module_entries/1)
      |> Map.new()
    end)
  end

  # The module an interface's functions are generated on: the host, or its namespace module, nil
  # when Ash generated none (its name was never made an atom).
  defp interface_module(host, nil), do: host

  defp interface_module(host, namespace) do
    Module.safe_concat(host, namespace)
  rescue
    ArgumentError -> nil
  end

  # The interface's function names, as strings, by form (see summary/2).
  defp interface_names(%{__struct__: Ash.Resource.CalculationInterface, name: name}, _resource) do
    {safe, bang} = safe_and_bang(name)
    [{safe, :calculation}, {bang, :calculation!}]
  end

  defp interface_names(%{name: name, functions: functions} = interface, resource) do
    {safe, bang} = safe_and_bang(name)

    subject =
      case interface_action(resource, interface).type do
        :read -> "query"
        :action -> "input"
        _type -> "changeset"
      end

    [
      {:action, safe, :action},
      {:action!, bang, :action!},
      {:can, "can_" <> safe, :can},
      {:can?, "can_" <> safe <> "?", :can?},
      {:subject, subject <> "_to_" <> Atom.to_string(name), :subject}
    ]
    |> Enum.filter(fn {function, _name, _form} -> function in functions end)
    |> Enum.map(fn {_function, name, form} -> {name, form} end)
  end

  # What the interface's function in the given form gives (see summary/2).
  defp interface_tree(resource, interface, :calculation!, flow),
    do: calculation_tree(resource, interface, flow)

  defp interface_tree(resource, interface, :calculation, flow),
    do: wrapped(calculation_tree(resource, interface, flow), resource, flow)

  defp interface_tree(resource, interface, :action!, flow),
    do: action_tree(resource, interface, flow)

  defp interface_tree(resource, interface, :action, flow) do
    tree = action_tree(resource, interface, flow)

    case interface_action(resource, interface).type do
      type when type in [:action, :destroy] ->
        union([[{:atom, :ok}], wrapped(tree, resource, flow)])

      _type ->
        wrapped(tree, resource, flow)
    end
  end

  defp interface_tree(_resource, _interface, :can?, _flow), do: [:prim]

  defp interface_tree(resource, interface, :can, flow) do
    subject = subject_tree(subject_module(resource, interface), resource, flow)
    ok = [{:atom, :ok}]

    union([
      [{:tuple, [ok, [:prim]]}, {:tuple, [ok, [:prim], subject]}],
      [{:tuple, [[{:atom, :error}], error_tree(resource, flow)]}]
    ])
  end

  defp interface_tree(resource, interface, :subject, flow),
    do: subject_tree(subject_module(resource, interface), resource, flow)

  # A record's field that Ash can leave not loaded: the field's shapes, nil, or `Ash.NotLoaded`,
  # which names the resource.
  defp loadable(tree, resource), do: union([tree, [:prim], not_loaded(resource)])

  # Whether Ash is loaded, asked once per compile (see available?/0): a compile without it asks for
  # every function.
  defp loaded?(flow), do: cached({__MODULE__, :available}, flow, &available?/0)

  # What the function gives, with Ash loaded (see summary/2).
  defp loaded_summary(Ash, function, arity, _flow),
    do: api_tree(function) || DataFlow.top({Ash, function, arity})

  defp loaded_summary(module, _function, 0, _flow) when module in @subjects,
    do: [{:struct, module, DataFlow.rest_fields([:prim])}]

  defp loaded_summary(module, _function, _arity, _flow) when module in @subjects,
    do: [{:rule, __MODULE__, :subject, [[{:atom, module}], [{:param, 0}]]}]

  defp loaded_summary(module, function, arity, flow) do
    index = interface_index(flow)

    case Map.fetch(index, {module, Atom.to_string(function)}) do
      {:ok, {resource, interface, form}} -> interface_tree(resource, interface, form, flow)
      :error -> if opaque?(module, flow), do: DataFlow.top({module, function, arity})
    end
  end

  defp map_tree(constraints, flow) do
    case constraints[:fields] do
      nil -> [{:map, DataFlow.rest_fields([:prim])}]
      fields -> [{:map, field_trees(fields, flow)}]
    end
  end

  # The functions the module's code interface generates, when it is a resource or a domain.
  defp module_entries(module) do
    cond do
      Info.resource?(module) -> resource_entries(module)
      Spark.Dsl.is?(module, Ash.Domain) -> domain_entries(module)
      true -> []
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

  # A record with its notifications, as a create, an update or a destroy gives it when asked for
  # them; the notification names the resource the given tree holds.
  defp notified(resource, record) do
    notification =
      struct_tree(Ash.Notifier.Notification, %{data: union([[:prim], record]), resource: resource})

    [{:tuple, [record, [{:list, notification}]]}]
  end

  # Whether the module is one of Ash's or its extensions' that no rule answers, and the app did not
  # define (its source under the project root, outside `deps`): its functions give their top (see
  # `Hologram.Compiler.DataFlow.top/1`), every type their code can give by the rule before the
  # analysis, instead of being followed through the framework's internals, where the analysis spent
  # minutes (M1, M4).
  defp opaque?(module, flow) do
    name = Atom.to_string(module)
    String.starts_with?(name, @opaque_prefixes) and not project_module?(module, flow)
  end

  # A list of records, or a page of them.
  defp paged(list) do
    union([
      list,
      struct_tree(Ash.Page.Keyset, %{results: list}),
      struct_tree(Ash.Page.Offset, %{results: list})
    ])
  end

  # Whether the module's source is the project's own: under its root, outside `deps`.
  defp project_module?(module, flow) do
    source =
      case PLT.get(flow.module_info_plt, module) do
        {:ok, %{source_path: source}} when is_binary(source) -> source
        _other -> Reflection.source_path(module)
      end

    root = Reflection.root_dir() <> "/"
    String.starts_with?(source, root) and not String.starts_with?(source, root <> "deps/")
  end

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

  # A read's records: the record or nil when it gets one, else a list of them, or a page of them
  # when the action paginates.
  defp read_tree(record, interface, action) do
    list = [{:list, record}]

    cond do
      interface.get? || action.get? || interface.get_by || interface.get_by_identity ->
        union([record, [:prim]])

      action.pagination ->
        paged(list)

      true ->
        list
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

  # The records of the resources among the modules, or every resource's when there is none.
  defp records_of(modules, flow) do
    case resources_among(modules) do
      [] ->
        all_records(flow)

      resources ->
        resources
        |> Enum.map(&record_shapes(&1, flow))
        |> union()
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

  # The functions a resource's code interface generates, on the resource or on its namespace module.
  defp resource_entries(resource) do
    namespace = Extension.get_opt(resource, [:code_interface], :namespace, nil)

    for interface <- Info.interfaces(resource) ++ Info.calculation_interfaces(resource),
        entry <- interface_entries(resource, resource, interface, namespace),
        do: entry
  end

  # The resources among the compile's modules.
  defp resources(flow) do
    cached({__MODULE__, :resources}, flow, fn ->
      flow.module_info_plt
      |> PLT.get_all()
      |> Map.keys()
      |> Enum.filter(&Info.resource?/1)
      |> Enum.sort()
    end)
  end

  # The resources among the modules.
  defp resources_among(modules), do: Enum.filter(modules, &Info.resource?/1)

  # What a generic action returns: its return type's shapes, or `:ok` without one.
  defp returns_tree(action, flow) do
    case action.returns do
      nil -> [{:atom, :ok}]
      type -> type_shapes(type, action.constraints || [], flow)
    end
  end

  # A name and the name of its form that raises, as Ash names them (a name ending in `?` raises), as
  # strings: the index is keyed by strings, so no atom is made for a name nothing calls.
  defp safe_and_bang(name) do
    string = Atom.to_string(name)

    if String.ends_with?(string, "?"),
      do: {String.trim_trailing(string, "?"), string},
      else: {string, string <> "!"}
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

  # The module of the subject the interface's action runs on: a query, a changeset or an action
  # input.
  defp subject_module(resource, interface) do
    case interface_action(resource, interface).type do
      :read -> Ash.Query
      :action -> Ash.ActionInput
      _type -> Ash.Changeset
    end
  end

  # A query, a changeset or an action input of the resource: its fields a rest holding the
  # resource's module (which Ash's functions called with it find it by) and its records.
  defp subject_tree(module, nil, flow) do
    rest =
      [[:prim], all_records(flow)]
      |> union()
      |> DataFlow.rest_fields()

    [{:struct, module, rest}]
  end

  defp subject_tree(module, resource, flow) do
    rest = union([[:prim, {:atom, resource}], record_shapes(resource, flow)])
    [{:struct, module, DataFlow.rest_fields(rest)}]
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

  # The given trees as one, sorted, each shape once (the analysis merges the shapes of a kind when
  # it interns the tree).
  defp union(trees) do
    trees
    |> Enum.concat()
    |> :lists.usort()
  end

  # A record's attributes, calculations and aggregates: each type's shapes and nil; an attribute can
  # also be a forbidden field, which may hold its original value, and a calculation or an aggregate
  # not loaded.
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

  # The tree as the forms that do not raise give it: `{:ok, tree}` or `{:error, error}`.
  defp wrapped(tree, resource, flow), do: wrapped_with(tree, error_tree(resource, flow))

  defp wrapped_with(tree, errors),
    do: [{:tuple, [[{:atom, :ok}], tree]}, {:tuple, [[{:atom, :error}], errors]}]
end
