defmodule Hologram.Query do
  @moduledoc false

  alias Hologram.Query.Placeholder
  alias Hologram.Reflection

  defmacro __using__(_opts) do
    quote do
      import Hologram.Query,
        only: [
          count: 1,
          filter: 2,
          include: 2,
          include: 3,
          limit: 2,
          offset: 2,
          one: 1,
          order_by: 2,
          paginate: 2
        ]

      alias Hologram.DB
      alias Hologram.Entity
    end
  end

  @directions [:asc, :desc]
  @equality_operators [:!=, :==]
  @membership_operators [:in, :not_in]
  @orderable_types [:date, :datetime, :enum, :float, :integer, :string]
  @ordering_operators [:<, :<=, :>, :>=]

  @doc """
  Marks the given query as counting and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. A counting query evaluates to a non-negative integer - the number of
  results the query otherwise evaluates to, view bounds included.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when a cardinality is already marked.
  """
  @spec count(module | %{atom => any}) :: %{atom => any}
  def count(query) do
    term = to_term(query)

    if term.cardinality != :set do
      raise ArgumentError,
        message: "cardinality is already set to #{inspect(term.cardinality)}"
    end

    %{term | cardinality: :count}
  end

  @doc """
  Appends predicates to the given query's filter list and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Predicates are a keyword list of attribute names (declared or system) and
  predicate values. A predicate value is a plain value (equality), an operator tuple -
  `{:==, value}`, `{:!=, value}`, `{:in, list}`, `{:not_in, list}`, or an ordering
  comparison `{:<, value}`, `{:<=, value}`, `{:>, value}`, `{:>=, value}` - a bare
  list of plain values (membership shorthand for `{:in, list}`), or a list of operator
  tuples applying all of them to the attribute (an AND conjunction, e.g.
  `[{:>=, monday}, {:<, next_monday}]`). Lists mixing plain values and operator tuples
  are invalid. Each predicate becomes one or more `{attribute, operator, value}`
  triples, appended in the given order. A query term is a plain-data description of a
  query - building it never executes anything.

  Ordering comparisons require an orderable attribute - every type but boolean and uuid -
  and a non-nil operand - SQL comparisons with NULL never match, so a nil operand would
  mean different things on the two execution tiers. A comparison on an enum attribute
  reads the declared `values:` order, so `{:>=, :medium}` on `[:low, :medium, :high]`
  means medium or high, and the operand must be one of the declared values. A comparison
  on a string attribute reads the order `order_by` sorts it in - case and diacritics fold
  the way they do in the list - and a bound names a position in that list, spelled the way
  the list spells it: `{:>=, "M"}` reaches `M`, `m`, `Mango`, while `{:>=, "m"}` starts at
  `m`.

  An integer Range value (`3..10`, bare or as `{:in, range}`) is shorthand for the
  inclusive bounds - it expands into a `>=` triple and a `<=` triple. Ranges require
  an integer attribute, step 1, and at least one element.

  Membership lists must be non-empty lists of plain values. Nil is a regular value:
  a nil element means the membership matches missing values too (`[nil, :done]` reads
  "done or unset"), and negated membership without nil matches missing values.

  A `Hologram.Query.Placeholder` struct in a value position - bare, as an operator-tuple
  operand, or as a membership list element - stands for a runtime-bound value: the
  triple stores a `{:placeholder, name}` leaf instead of a concrete value, and value
  validation is skipped (the concrete value is validated when the placeholder binds at
  execution). A membership-element placeholder binds a single value of the attribute's
  type. Ordering comparisons still require an orderable attribute.

  A placeholder also stands where an ordering key or its direction goes (`order_by(query, sort)`,
  `order_by(query, name: dir)`), where a view bound goes (`limit(query, size)`,
  `offset(query, start)`), and where a filtered attribute's name goes
  (`filter(query, [{attribute, value}])`), storing a `{:placeholder, name}` leaf in place of the
  attribute, the direction or the bound, and skipping the checks that would need a concrete
  one. A placeholder-keyed predicate leaves its operand unchecked too - the attribute's type is
  unknown, so nothing about the operand can be judged against it.

  A leaf names the ARGUMENT a value came from, not the value: a computed operand carries the name
  of the argument it derives from, so `b: n * 2` stores `{:placeholder, :n}`. Nothing binds a leaf
  back to a value - both execution tiers call the builder with real values and normalize THAT - so
  the name serves reading a term, never evaluating one.

  To-one reference fields (`<relationship name>_id`) are filterable alongside attributes -
  they carry the `:uuid` type, so they take equality, membership and placeholder values, while
  ordering comparisons and ranges reject them like any other non-orderable type. To-many
  relationships have no reference field, and neither relationship name itself is filterable.

  Raises ArgumentError when the query is neither an entity type module nor a query term,
  when the predicates are not a keyword list, when a predicate names a relationship or
  an unknown attribute, or when a predicate value is invalid (unknown operator, invalid
  membership list, list or tuple operand for an equality operator).
  """
  @spec filter(module | %{atom => any}, keyword) :: %{atom => any}
  def filter(query, predicates) do
    term = to_term(query)

    if not filterable_predicates?(predicates) do
      raise ArgumentError,
        message: "filter predicates must be a keyword list, got: #{inspect(predicates)}"
    end

    triples = predicate_triples!(term.entity, predicates)

    %{term | filter: term.filter ++ triples}
  end

  @doc """
  Adds relationship traversals to the given query's include map and returns the
  resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Relationships must be declared on the query's entity type - the whole
  related entity (to-one) or entity set (to-many) is embedded in results under the
  relationship's name.

  The spec is a relationship name, or a shape list describing a traversal tree as
  data: entries are relationship names, `{name, nested_spec}` pairs traversing deeper
  (keyword syntax reads naturally - `include(query, project: :owner)`,
  `include(query, [:assignee, project: :owner])`), or `{name, sub_builder}` pairs.
  A sub-builder is a one-argument function receiving the related entity's base query
  term and returning a refined query term for the same entity - to-many includes take
  nested clauses this way. `include/3` passes a sub-builder for a single relationship
  name directly.

  To-one includes take no clauses (a single embedded entity has nothing to filter,
  order, or slice) - nested includes are their only refinement. Traversal depth is
  limited to 2 levels.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, when the spec is invalid or empty, when a name is not a declared relationship,
  when a relationship is already included, when a sub-builder is not a one-argument
  function or does not return a query term for the related entity type, when a to-one
  include carries clauses, or when the include depth exceeds 2 levels.
  """
  @spec include(
          module | %{atom => any},
          atom | list,
          (%{atom => any} -> %{atom => any}) | nil
        ) :: %{atom => any}
  def include(query, spec, sub_builder \\ nil)

  def include(query, name, nil) when is_atom(name) do
    include(query, name, fn related_term -> related_term end)
  end

  def include(query, name, sub_builder) when is_atom(name) and is_function(sub_builder, 1) do
    term = to_term(query)

    {target, kind} = validate_relationship_name!(name, term.entity)

    if Map.has_key?(term.include, name) do
      raise ArgumentError,
        message: "relationship #{inspect(name)} is already included"
    end

    related_base_term = to_term(target)
    sub_term = sub_builder.(related_base_term)

    validate_sub_term!(sub_term, name, target, kind)

    %{term | include: Map.put(term.include, name, sub_term)}
  end

  def include(query, spec, nil) when is_list(spec) do
    if spec == [] do
      raise ArgumentError, message: "include spec must not be empty"
    end

    term = to_term(query)

    Enum.reduce(spec, term, fn entry, acc -> include_spec_entry!(acc, entry) end)
  end

  def include(_query, name, sub_builder) when is_atom(name) do
    raise ArgumentError,
      message:
        "include sub-builder for relationship #{inspect(name)} must be a one-argument function, got: #{inspect(sub_builder)}"
  end

  def include(_query, spec, _sub_builder) when is_list(spec) do
    raise ArgumentError,
      message:
        "an include shape spec takes no separate sub-builder - nest it in the spec as a {name, sub_builder} pair"
  end

  def include(_query, spec, _sub_builder) do
    raise ArgumentError,
      message: "include spec must be a relationship name or a shape list, got: #{inspect(spec)}"
  end

  @doc """
  Sets the given query's limit - the maximum number of results the query evaluates
  to - and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The limit is a non-negative integer. It bounds what the query evaluates
  to, not the underlying data. A later call replaces a limit an earlier one set.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when the limit is not a non-negative integer.
  """
  @spec limit(module | %{atom => any}, non_neg_integer) :: %{atom => any}
  def limit(query, value) do
    set_view_bound!(query, :limit, value)
  end

  # Returns the canonical form of the given query - the form executors run literally
  # and the registry hashes. Normalization: sorts filter predicates into canonical
  # order (conjunction is commutative), gives every set-returning shape a total
  # deterministic order by appending an ascending id tiebreaker (or the id ordering
  # itself when no ordering is set) unless id is already among the ordering keys,
  # drops the ordering from counting queries (counts are order-invariant, view bounds
  # included), and normalizes included sub-terms recursively - to-one includes embed
  # a single entity and carry no ordering. Idempotent.
  @doc false
  @spec normalize(module | %{atom => any}) :: %{atom => any}
  def normalize(query) do
    query
    |> to_term()
    |> normalized_term()
  end

  @doc """
  Sets the given query's offset - the number of results skipped before the query's
  results begin - and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The offset is a non-negative integer. It slices what the query evaluates
  to, not the underlying data. A later call replaces an offset an earlier one set.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when the offset is not a non-negative integer.
  """
  @spec offset(module | %{atom => any}, non_neg_integer) :: %{atom => any}
  def offset(query, value) do
    set_view_bound!(query, :offset, value)
  end

  @doc """
  Marks the given query as single-result and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. A single-result query evaluates to the first entity under the query's
  total order, or nil when no entity matches - never an error on multiplicity, since
  live re-evaluation makes transient multiplicity a normal state.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, or when a cardinality is already marked.
  """
  @spec one(module | %{atom => any}) :: %{atom => any}
  def one(query) do
    term = to_term(query)

    if term.cardinality != :set do
      raise ArgumentError,
        message: "cardinality is already set to #{inspect(term.cardinality)}"
    end

    %{term | cardinality: :one}
  end

  @doc """
  Sets the given query's ordering keys and returns the resulting query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The spec is an attribute name (ascending), or a list whose entries are
  attribute names (ascending) or `{attribute, :asc | :desc}` tuples - keyword syntax
  reads naturally (`order_by(query, title: :desc)`). Each entry becomes an
  `{attribute, direction}` pair, in the given order.

  An ordering is atomic - a later call replaces the ordering an earlier one set rather
  than adding to it. Precedence is positional, so an ordering states itself in one place
  or not at all.

  An enum attribute orders by the position of its values in the declared `values:` list -
  `[:low, :medium, :high]` sorts low, medium, high, on both execution tiers.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, when the spec is neither an attribute name nor a list, when an entry names a
  relationship or an unknown attribute, or when a direction is neither :asc nor :desc.
  """
  @spec order_by(module | %{atom => any}, atom | list) :: %{atom => any}
  def order_by(query, spec) do
    term = to_term(query)

    entries = order_entries!(spec, term.entity)

    %{term | order_by: entries}
  end

  @doc """
  Sets the given query's view bounds to the requested page and returns the resulting
  query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Options are `page:` (a positive integer, 1-based) and `size:` (a positive
  integer, the number of results per page), both required. Pagination expands into the
  offset and limit view bounds - `paginate(page: 2, size: 20)` sets offset 20 and
  limit 20 - and slices what the query evaluates to, not the underlying data, replacing
  view bounds already set. Either option may be a placeholder, which makes the bounds it feeds
  placeholders too.

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, when the options are not a keyword list holding exactly :page and :size, or when
  either option is not a positive integer.
  """
  @spec paginate(module | %{atom => any}, keyword) :: %{atom => any}
  def paginate(query, opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
        message: "paginate options must be a keyword list, got: #{inspect(opts)}"
    end

    unknown_keys = Keyword.keys(opts) -- [:page, :size]

    if unknown_keys != [] do
      raise ArgumentError,
        message:
          "unknown paginate option #{inspect(hd(unknown_keys))} - supported options: :page, :size"
    end

    page = validate_paginate_option!(opts, :page)
    size = validate_paginate_option!(opts, :size)

    query
    |> offset(paginate_offset(page, size))
    |> limit(size)
  end

  @doc """
  Returns the names of every placeholder leaf in the given query term, filter attributes and
  values, view bounds, ordering keys and directions, and include sub-terms included - an
  empty list for a term with concrete values only.
  """
  @spec placeholder_names(%{atom => any}) :: list(atom)
  def placeholder_names(term) do
    filter_names =
      term
      |> Map.get(:filter, [])
      |> Enum.flat_map(fn {name, _operator, value} ->
        value_placeholder_names(name) ++ value_placeholder_names(value)
      end)

    bound_names =
      [:limit, :offset]
      |> Enum.map(&Map.get(term, &1))
      |> Enum.flat_map(&value_placeholder_names/1)

    order_names =
      term
      |> Map.get(:order_by, [])
      |> Enum.flat_map(fn {key, direction} ->
        value_placeholder_names(key) ++ value_placeholder_names(direction)
      end)

    include_names =
      term
      |> Map.get(:include, %{})
      |> Map.values()
      |> Enum.flat_map(&placeholder_names/1)

    filter_names ++ bound_names ++ order_names ++ include_names
  end

  @doc false
  @spec predicate_triples!(module, keyword) :: list({atom, atom, any})
  def predicate_triples!(entity_type, predicates) do
    Enum.flat_map(predicates, fn
      {%Placeholder{name: placeholder_name}, value} ->
        [placeholder_key_triple(placeholder_name, value)]

      {name, value} ->
        validate_filtered_name!(name, entity_type)
        predicate_triples!(name, value, entity_type)
    end)
  end

  defp attribute_names(entity_type) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    definitions
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.sort()
  end

  defp attribute_definition(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end)
  end

  # Names reach type lookups already validated, so a name matching no attribute definition
  # is a to-one reference field - every reference column carries the entity id type.
  defp attribute_type(entity_type, name) do
    case attribute_definition(entity_type, name) do
      {_name, type, _opts} -> type
      nil -> :uuid
    end
  end

  defp constraint_tuple?(value) do
    is_tuple(value) and tuple_size(value) == 2 and is_atom(elem(value, 0))
  end

  # Keyword.keyword?/1 with placeholder keys admitted - a placeholder names an attribute nobody knows yet.
  defp filterable_predicates?(predicates) when is_list(predicates) do
    Enum.all?(predicates, fn
      {%Placeholder{}, _value} -> true
      {name, _value} when is_atom(name) -> true
      _entry -> false
    end)
  end

  defp filterable_predicates?(_predicates), do: false

  # Nothing about a placeholder-keyed predicate can be checked - the attribute is unknown, so its type,
  # its operators and its operand's shape are all unknown with it. The triple records what was
  # written and Hologram.Query.Window drops it from the download, the real builder validating for
  # real once the attribute arrives.
  defp placeholder_key_triple(placeholder_name, {operator, value}) when is_atom(operator) do
    {{:placeholder, placeholder_name}, operator, placeholder_operand(value)}
  end

  defp placeholder_key_triple(placeholder_name, value) do
    {{:placeholder, placeholder_name}, :==, placeholder_operand(value)}
  end

  defp placeholder_operand(%Placeholder{name: placeholder_name}),
    do: {:placeholder, placeholder_name}

  defp placeholder_operand(values) when is_list(values), do: normalize_membership_values(values)

  defp placeholder_operand(value), do: value

  defp filterable_names(entity_type) do
    Enum.sort(attribute_names(entity_type) ++ reference_field_names(entity_type))
  end

  defp equality_triple!(name, operator, operand) do
    if is_list(operand) or is_tuple(operand) or is_struct(operand, Range) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect(name)}"
    end

    {name, operator, operand}
  end

  defp include_depth(term) do
    if term.include == %{} do
      0
    else
      max_child_depth =
        term.include
        |> Map.values()
        |> Enum.map(&include_depth/1)
        |> Enum.max()

      1 + max_child_depth
    end
  end

  defp include_spec_entry!(term, name) when is_atom(name) do
    include(term, name)
  end

  defp include_spec_entry!(term, {name, sub_builder})
       when is_atom(name) and is_function(sub_builder) do
    include(term, name, sub_builder)
  end

  defp include_spec_entry!(term, {name, sub_spec}) when is_atom(name) do
    include(term, name, fn related_term -> include(related_term, sub_spec) end)
  end

  defp include_spec_entry!(_term, entry) do
    raise ArgumentError,
      message:
        "invalid include spec entry #{inspect(entry)} - use a relationship name, a {name, spec} pair, or a {name, sub_builder} pair"
  end

  defp normalized_includes(term) do
    Map.new(term.include, fn {name, sub_term} ->
      {name, normalized_sub_term(sub_term, relationship_kind(term.entity, name))}
    end)
  end

  defp normalized_order(term) do
    ordering_keys = Enum.map(term.order_by, fn {name, _direction} -> name end)

    cond do
      term.cardinality == :count -> []
      :id in ordering_keys -> term.order_by
      true -> List.insert_at(term.order_by, -1, {:id, :asc})
    end
  end

  defp normalized_sub_term(sub_term, :to_many), do: normalized_term(sub_term)

  defp normalized_sub_term(sub_term, :to_one) do
    %{sub_term | include: normalized_includes(sub_term)}
  end

  defp normalized_term(term) do
    %{
      term
      | filter: Enum.sort(term.filter),
        include: normalized_includes(term),
        order_by: normalized_order(term)
    }
  end

  defp order_direction!(%Placeholder{name: placeholder_name}, _key),
    do: {:placeholder, placeholder_name}

  defp order_direction!(direction, _key) when direction in @directions, do: direction

  defp order_direction!(direction, key) do
    raise ArgumentError,
      message:
        "invalid direction #{inspect(direction)} for attribute #{inspect(key)} - use :asc or :desc"
  end

  # A placeholder spec binds either a single ordering key or a whole spec list at execution - the build
  # cannot tell which, and does not need to: the registered term's ordering is dead weight, since
  # Hologram.Query.Window empties it. One entry stands for whatever arrives.
  defp order_entries!(%Placeholder{name: placeholder_name}, _entity_type) do
    [{{:placeholder, placeholder_name}, :asc}]
  end

  defp order_entries!(name, entity_type) when is_atom(name) do
    [order_entry!(name, entity_type)]
  end

  defp order_entries!(spec, entity_type) when is_list(spec) do
    Enum.map(spec, &order_entry!(&1, entity_type))
  end

  defp order_entries!(spec, _entity_type) do
    raise ArgumentError,
      message: "order_by spec must be an attribute name or a list, got: #{inspect(spec)}"
  end

  defp normalize_membership_values(values) do
    Enum.map(values, fn
      %Placeholder{name: placeholder_name} -> {:placeholder, placeholder_name}
      value -> value
    end)
  end

  defp order_entry!({name, direction}, entity_type) when is_atom(name) do
    validate_attribute_name!(name, entity_type, "ordered")

    {name, order_direction!(direction, name)}
  end

  defp order_entry!({%Placeholder{name: placeholder_name}, direction}, _entity_type) do
    key = {:placeholder, placeholder_name}

    {key, order_direction!(direction, key)}
  end

  defp order_entry!(%Placeholder{name: placeholder_name}, _entity_type) do
    {{:placeholder, placeholder_name}, :asc}
  end

  defp order_entry!(name, entity_type) when is_atom(name) do
    validate_attribute_name!(name, entity_type, "ordered")

    {name, :asc}
  end

  defp order_entry!(entry, _entity_type) do
    raise ArgumentError,
      message:
        "invalid order_by entry #{inspect(entry)} - use an attribute name or an {attribute, :asc | :desc} tuple"
  end

  # The offset a page produces depends on both options, so a placeholder in either makes it one too -
  # named for whichever option it varies with, page first.
  #
  # THE NAME IS NOT A BINDING KEY. A leaf names the ARGUMENT a value derives from, never the value
  # itself, which is why `offset((page - 1) * size)` written out by hand yields this same leaf, and
  # why `filter(b: n * 2)` yields `{:b, :==, {:placeholder, :n}}`. Nothing ever turns a leaf back
  # into a value: both tiers call the real builder with the component's real props, so the offset
  # that executes is the computed one.
  defp paginate_offset(%Placeholder{} = page, _size), do: page

  defp paginate_offset(_page, %Placeholder{} = size), do: size

  defp paginate_offset(page, size), do: (page - 1) * size

  defp ordering_triple!(name, operator, operand, entity_type) do
    validate_orderable_attribute!(name, entity_type, operator)

    if is_nil(operand) or is_list(operand) or is_tuple(operand) or is_struct(operand, Range) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect(name)}"
    end

    validate_enum_operand!(name, operand, entity_type)

    {name, operator, operand}
  end

  defp predicate_triples!(name, {:in, %Range{} = range}, entity_type) do
    predicate_triples!(name, range, entity_type)
  end

  defp predicate_triples!(name, %Range{} = range, entity_type) do
    validate_membership_range!(range, name, entity_type)

    [{name, :>=, range.first}, {name, :<=, range.last}]
  end

  defp predicate_triples!(name, %Placeholder{name: placeholder_name}, _entity_type) do
    [{name, :==, {:placeholder, placeholder_name}}]
  end

  defp predicate_triples!(name, {operator, %Placeholder{name: placeholder_name}}, entity_type)
       when is_atom(operator) do
    cond do
      operator in @equality_operators or operator in @membership_operators ->
        [{name, operator, {:placeholder, placeholder_name}}]

      operator in @ordering_operators ->
        validate_orderable_attribute!(name, entity_type, operator)
        [{name, operator, {:placeholder, placeholder_name}}]

      true ->
        raise_unknown_operator!(operator, name)
    end
  end

  defp predicate_triples!(name, {:actor}, entity_type) do
    validate_actor_attribute!(name, entity_type)

    [{name, :==, {:actor}}]
  end

  defp predicate_triples!(name, {operator, {:actor}}, entity_type)
       when operator in @equality_operators do
    validate_actor_attribute!(name, entity_type)

    [{name, operator, {:actor}}]
  end

  defp predicate_triples!(name, {operator, operand}, entity_type) when is_atom(operator) do
    cond do
      operator in @equality_operators ->
        [equality_triple!(name, operator, operand)]

      operator in @membership_operators ->
        validate_membership_list!(operand, name, operator)
        [{name, operator, normalize_membership_values(operand)}]

      operator in @ordering_operators ->
        [ordering_triple!(name, operator, operand, entity_type)]

      true ->
        raise_unknown_operator!(operator, name)
    end
  end

  defp predicate_triples!(name, value, _entity_type) when is_tuple(value) do
    raise ArgumentError,
      message: "invalid filter value #{inspect(value)} for attribute #{inspect(name)}"
  end

  defp predicate_triples!(name, values, entity_type) when is_list(values) do
    cond do
      values == [] ->
        raise ArgumentError,
          message: "filter list for attribute #{inspect(name)} must not be empty"

      Enum.all?(values, &constraint_tuple?/1) ->
        Enum.flat_map(values, fn value -> predicate_triples!(name, value, entity_type) end)

      Enum.all?(values, &plain_value?/1) ->
        validate_membership_list!(values, name, :in)
        [{name, :in, normalize_membership_values(values)}]

      true ->
        raise ArgumentError,
          message:
            "invalid filter list #{inspect(values)} for attribute #{inspect(name)} - use either a membership list of plain values or a list of operator tuples"
    end
  end

  defp predicate_triples!(name, value, _entity_type), do: [{name, :==, value}]

  defp plain_value?(value) do
    not is_tuple(value) and not is_list(value) and not is_struct(value, Range)
  end

  defp raise_unknown_operator!(operator, name) do
    raise ArgumentError,
      message:
        "unknown operator #{inspect(operator)} in the filter predicate for attribute #{inspect(name)} - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"
  end

  defp reference_field_names(entity_type) do
    entity_type
    |> to_one_relationship_names()
    |> Enum.map(&String.to_existing_atom("#{&1}_id"))
  end

  defp relationship_kind(entity_type, name) do
    {_target, kind} = validate_relationship_name!(name, entity_type)

    kind
  end

  defp relationship_names(entity_type) do
    Enum.map(entity_type.__relationships__(), fn {name, _type, _opts} -> name end)
  end

  defp set_view_bound!(query, field, %Placeholder{name: placeholder_name}) do
    term = to_term(query)

    Map.put(term, field, {:placeholder, placeholder_name})
  end

  defp set_view_bound!(query, field, value) do
    term = to_term(query)

    if not is_integer(value) or value < 0 do
      raise ArgumentError,
        message: "#{field} must be a non-negative integer, got: #{inspect(value)}"
    end

    Map.put(term, field, value)
  end

  defp sub_term_has_clauses?(sub_term) do
    sub_term.filter != [] or sub_term.order_by != [] or sub_term.limit != nil or
      sub_term.offset != nil
  end

  defp to_one_relationship_names(entity_type) do
    entity_type.__relationships__()
    |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  defp to_term(%{entity: _entity_type} = term), do: term

  defp to_term(query) do
    if Reflection.entity?(query) do
      %{
        cardinality: :set,
        entity: query,
        filter: [],
        include: %{},
        limit: nil,
        offset: nil,
        order_by: []
      }
    else
      raise ArgumentError,
        message:
          "#{inspect(query)} is not an entity type module or a query term - a query starts from a module with the \"use Hologram.Entity\" directive"
    end
  end

  # The actor leaf carries the acting user's entity id, so it compares only against names
  # holding an entity id - any other type would compile a comparison that never matches.
  defp validate_actor_attribute!(name, entity_type) do
    type = attribute_type(entity_type, name)

    if type != :uuid do
      raise ArgumentError,
        message:
          "user_id() requires a uuid attribute - attribute #{inspect(name)} in #{inspect(entity_type)} has type #{inspect(type)}"
    end
  end

  defp validate_attribute_name!(name, entity_type, usage) do
    attribute_names = attribute_names(entity_type)

    cond do
      name in attribute_names ->
        :ok

      name in relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be #{usage}"

      true ->
        known = Enum.map_join(attribute_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown attribute #{inspect(name)} in #{inspect(entity_type)} - known attributes: #{known}"
    end
  end

  defp validate_filtered_name!(name, entity_type) do
    filterable_names = filterable_names(entity_type)

    cond do
      name in filterable_names ->
        :ok

      name in to_one_relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be filtered - filter its reference via :#{name}_id"

      name in relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be filtered"

      true ->
        known = Enum.map_join(filterable_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown attribute #{inspect(name)} in #{inspect(entity_type)} - known attributes: #{known}"
    end
  end

  # A comparison operand on an enum is one of the values it declares, refused where it is written
  # rather than where it is run: the database refuses an undeclared label too, but only once the
  # statement reaches it, and by then nothing can name the values there were to choose from.
  defp validate_enum_operand!(name, operand, entity_type) do
    case attribute_definition(entity_type, name) do
      {_name, :enum, opts} ->
        values = Keyword.fetch!(opts, :values)

        if operand not in values do
          raise ArgumentError,
            message:
              "#{inspect(operand)} is not a value of attribute #{inspect(name)} in #{inspect(entity_type)} - the values are #{inspect(values)}"
        end

      _other ->
        :ok
    end
  end

  defp validate_membership_list!(values, name, _operator) when is_list(values) do
    if values == [] do
      raise ArgumentError,
        message: "membership list for attribute #{inspect(name)} must not be empty"
    end

    Enum.each(values, fn
      value when is_list(value) or is_tuple(value) ->
        raise ArgumentError,
          message:
            "invalid membership list element #{inspect(value)} for attribute #{inspect(name)} - membership lists hold plain values"

      %Range{} = value ->
        raise ArgumentError,
          message:
            "invalid membership list element #{inspect(value)} for attribute #{inspect(name)} - membership lists hold plain values"

      _value ->
        :ok
    end)
  end

  defp validate_membership_list!(operand, name, operator) do
    raise ArgumentError,
      message:
        "operator #{inspect(operator)} on attribute #{inspect(name)} requires a list operand, got: #{inspect(operand)}"
  end

  defp validate_membership_range!(range, name, entity_type) do
    type = attribute_type(entity_type, name)

    if type != :integer do
      raise ArgumentError,
        message:
          "range #{inspect(range)} requires an integer attribute - attribute #{inspect(name)} in #{inspect(entity_type)} has type #{inspect(type)}"
    end

    if range.step != 1 do
      raise ArgumentError,
        message:
          "stepped range #{inspect(range)} for attribute #{inspect(name)} is not supported - membership ranges use step 1"
    end

    if Range.size(range) == 0 do
      raise ArgumentError,
        message:
          "range #{inspect(range)} for attribute #{inspect(name)} is empty - it would match nothing"
    end
  end

  defp validate_orderable_attribute!(name, entity_type, operator) do
    type = attribute_type(entity_type, name)

    if type not in @orderable_types do
      raise ArgumentError,
        message:
          "operator #{inspect(operator)} requires an orderable attribute - attribute #{inspect(name)} in #{inspect(entity_type)} has type #{inspect(type)}, and boolean and uuid attributes have no order to compare by"
    end
  end

  defp validate_paginate_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, %Placeholder{} = placeholder} ->
        placeholder

      {:ok, value} when is_integer(value) and value >= 1 ->
        value

      {:ok, value} ->
        raise ArgumentError,
          message: "#{key} must be a positive integer, got: #{inspect(value)}"

      :error ->
        raise ArgumentError, message: "paginate requires the #{inspect(key)} option"
    end
  end

  defp validate_relationship_name!(name, entity_type) do
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end) do
      {_name, [target], _opts} ->
        {target, :to_many}

      {_name, target, _opts} ->
        {target, :to_one}

      nil ->
        if name in attribute_names(entity_type) do
          raise ArgumentError,
            message:
              "#{inspect(name)} is an attribute in #{inspect(entity_type)} - only relationships can be included"
        end

        relationship_names = relationship_names(entity_type)
        known = Enum.map_join(relationship_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown relationship #{inspect(name)} in #{inspect(entity_type)} - known relationships: #{known}"
    end
  end

  defp validate_sub_term!(sub_term, name, target, kind) do
    validate_sub_term_entity!(sub_term, name, target)

    if sub_term.cardinality != :set do
      raise ArgumentError,
        message:
          "include sub-terms take no cardinality marker - the relationship declaration governs cardinality"
    end

    if kind == :to_one and sub_term_has_clauses?(sub_term) do
      raise ArgumentError,
        message:
          "to-one relationship #{inspect(name)} takes no clauses - clauses apply to to-many includes"
    end

    if include_depth(sub_term) > 1 do
      raise ArgumentError,
        message: "including #{inspect(name)} exceeds the traversal depth limit of 2 levels"
    end
  end

  defp validate_sub_term_entity!(%{entity: target}, _name, target), do: :ok

  defp validate_sub_term_entity!(%{entity: other_entity_type}, name, target) do
    raise ArgumentError,
      message:
        "include sub-builder for relationship #{inspect(name)} must return a query term for #{inspect(target)} - got a query term for #{inspect(other_entity_type)}"
  end

  defp validate_sub_term_entity!(sub_term, name, target) do
    raise ArgumentError,
      message:
        "include sub-builder for relationship #{inspect(name)} must return a query term for #{inspect(target)}, got: #{inspect(sub_term)}"
  end

  defp value_placeholder_names({:placeholder, name}), do: [name]

  defp value_placeholder_names(values) when is_list(values),
    do: Enum.flat_map(values, &value_placeholder_names/1)

  defp value_placeholder_names(_value), do: []
end
