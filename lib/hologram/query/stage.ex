defmodule Hologram.Query.Stage do
  @moduledoc false

  # What Hologram.Query's stages run: the query stages and the entity-struct stages, over the data
  # form - lists pairing attribute names or paths with predicate values, operator tuples,
  # membership lists, ranges and placeholders. Hologram.Query delegates its stages here, or expands to them
  # from the stages written in the query syntax, and documents them there. Normalization,
  # placeholder listing and the predicate triples policies share are framework internals, called
  # on this module directly.

  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Reflection

  @directions [:asc, :desc]
  @equality_operators [:!=, :==]
  @membership_operators [:in, :not_in]
  @orderable_types [:date, :datetime, :enum, :float, :integer, :string, :time]
  @ordering_operators [:<, :<=, :>, :>=]

  # The type pairs whose attributes compare though their types differ, compared on the wider type -
  # a widening keeps the value's meaning. An integer is the same number as a float. A date is not a
  # datetime: it becomes one instant only once a time zone is picked, and a comparison against it
  # means the day an instant falls on, which no widening says.
  @widenings [{:float, :integer}, {:integer, :float}]

  @doc false
  @spec add_relationship(Entity.t(), atom, Entity.id()) :: Entity.t()
  def add_relationship(entity, relationship_name, target_id) do
    put_relationship_op(entity, relationship_name, target_id, :add, "add_relationship")
  end

  @doc false
  @spec authorize(Entity.t(), atom) :: Entity.t()
  def authorize(entity, operation) when is_atom(operation) do
    entity_type = entity_type!(entity, "authorize")

    Policy.validate_operation!(entity_type, operation)

    put_claim(entity, {:authorize, operation}, "authorize")
  end

  def authorize(_entity, operation) do
    raise ArgumentError, message: "authorize takes an operation atom, got: #{inspect(operation)}"
  end

  @doc false
  @spec count(module | Query.t()) :: Query.t()
  def count(query) do
    term = to_term(query)

    if term.cardinality != :set do
      raise ArgumentError,
        message: "cardinality is already set to #{inspect(term.cardinality)}"
    end

    %{term | cardinality: :count}
  end

  @doc false
  @spec decrement(Entity.t(), atom, pos_integer) :: Entity.t()
  def decrement(entity, name, amount) do
    put_delta(entity, name, amount, -1, "decrement")
  end

  @doc false
  @spec delete_relationship(Entity.t(), atom, Entity.id()) :: Entity.t()
  def delete_relationship(entity, relationship_name, target_id) do
    put_relationship_op(entity, relationship_name, target_id, :delete, "delete_relationship")
  end

  # The data form a filter lowers to, and what filter(^predicates) passes as is: a list pairing
  # attribute names - or paths, below - with predicate values: a plain value (equality), an
  # operator tuple, a bare membership list, a list of operator tuples applying all of them (a
  # conjunction), or an integer range. An or: entry holding a list of at least two predicate lists
  # is a disjunction, which becomes one {:or, alternatives} clause, each alternative the clauses of
  # its list.
  #
  # An {:attribute, name} tuple in a value position - bare (equality) or as the operand of a
  # comparison operator - names another attribute of the same row, which the triple stores as is.
  # The two attributes have to compare: the same type, or one widening to the other, two enums
  # declaring the same values in the same order, and never one attribute with itself.
  #
  # A path - a list of two or more names, to-one relationships followed in order and a filterable
  # name of the row at the end - stands wherever an attribute name does, as a key or inside an
  # {:attribute, path} operand, and the triple stores it as is. It is checked by the declaration
  # of the name it ends at.
  #
  # A Hologram.Query.Placeholder struct in a value position - bare, as an operator-tuple operand,
  # or as a membership list element - stands for a runtime-bound value: the triple stores a
  # {:placeholder, name} leaf instead of a concrete value, and value validation is skipped (the
  # concrete value is validated when the placeholder binds at execution). A membership-element
  # placeholder binds a single value of the attribute's type, and an ordering comparison with a
  # placeholder operand still requires an orderable attribute. A placeholder also
  # stands where a filtered attribute's name goes ([{placeholder, value}]), an ordering key or
  # direction goes, or a view bound goes, storing a leaf in its place and skipping the checks that
  # would need a concrete one. A placeholder-keyed predicate leaves its operand unchecked too - the
  # attribute's type is unknown, so nothing about the operand can be judged against it.
  #
  # A leaf names the ARGUMENT a value came from, not the value: a computed operand carries the
  # name of the argument it derives from, so b: ^(n * 2) stores {:placeholder, :n}. Nothing binds a
  # leaf back to a value - both execution tiers call the builder with real values and normalize
  # THAT - so the name serves reading a term, never evaluating one.
  @doc false
  @spec filter(module | Query.t(), Query.predicates()) :: Query.t()
  def filter(query, predicates) do
    term = to_term(query)

    if not filterable_predicates?(predicates) do
      raise ArgumentError,
        message:
          "filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: #{inspect(predicates)}"
    end

    triples = predicate_triples!(term.entity, predicates)

    %{term | filter: term.filter ++ triples}
  end

  @doc false
  @spec include(module | Query.t(), atom | list, (Query.t() -> Query.t()) | nil) :: Query.t()
  def include(query, spec, sub_builder \\ nil)

  def include(query, name, nil) when is_atom(name) do
    include(query, name, fn related_term -> related_term end)
  end

  def include(query, name, sub_builder) when is_atom(name) and is_function(sub_builder, 1) do
    term = to_term(query)

    {target, kind} = validate_relationship_name!(name, term.entity)

    related_base_term = to_term(target)
    sub_term = sub_builder.(related_base_term)

    validate_sub_term!(sub_term, name, target, kind)

    %{term | include: put_included!(term.include, name, sub_term)}
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

  @doc false
  @spec increment(Entity.t(), atom, integer) :: Entity.t()
  def increment(entity, name, amount) do
    put_delta(entity, name, amount, 1, "increment")
  end

  # Returns a name as a message spells it: an attribute as inspect/1 does, a path as it is written.
  @doc false
  @spec inspect_name(atom | Query.path() | Query.placeholder()) :: String.t()
  def inspect_name(path) when is_list(path), do: Enum.join(path, ".")

  def inspect_name(name), do: inspect(name)

  # Returns the canonical form of the given query - the form executors run literally
  # and the registry hashes. Normalization: sorts filter clauses into canonical order,
  # disjunctions all the way down, gives every set-returning shape a total
  # deterministic order by appending an ascending id tiebreaker (or the id ordering
  # itself when no ordering is set) unless id is already among the ordering keys,
  # drops the ordering from counting queries (counts are order-invariant, view bounds
  # included), and normalizes included sub-terms recursively - to-one includes embed
  # a single entity and carry no ordering. Idempotent.
  @doc false
  @spec normalize(module | Query.t()) :: Query.t()
  def normalize(query) do
    query
    |> to_term()
    |> normalized_term()
  end

  # Returns the canonical order of the given filter clauses: every alternative of a disjunction
  # sorted, the alternatives sorted, and the clauses sorted - conjunction and disjunction are both
  # commutative, so two spellings of one query are one term only if the order goes all the way
  # down.
  @doc false
  @spec normalized_filter(list(Query.clause())) :: list(Query.clause())
  def normalized_filter(clauses) do
    clauses
    |> Enum.map(&normalized_clause/1)
    |> Enum.sort()
  end

  @doc false
  @spec offset(module | Query.t(), non_neg_integer) :: Query.t()
  def offset(query, value) do
    set_view_bound!(query, :offset, value)
  end

  @doc false
  @spec one(module | Query.t()) :: Query.t()
  def one(query) do
    term = to_term(query)

    if term.cardinality != :set do
      raise ArgumentError,
        message: "cardinality is already set to #{inspect(term.cardinality)}"
    end

    %{term | cardinality: :one}
  end

  @doc false
  @spec paginate(module | Query.t(), keyword) :: Query.t()
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
    |> take(size)
  end

  @doc """
  Returns the names of every placeholder leaf in the given query term, filter attributes and
  values, view bounds, ordering keys and directions, and include sub-terms included - an
  empty list for a term with concrete values only.
  """
  @spec placeholder_names(Query.t()) :: list(atom)
  def placeholder_names(term) do
    filter_names =
      term.filter
      |> triples()
      |> Enum.flat_map(fn {name, _operator, value} ->
        value_placeholder_names(name) ++ value_placeholder_names(value)
      end)

    bound_names = Enum.flat_map([term.take, term.offset], &value_placeholder_names/1)

    order_names =
      Enum.flat_map(term.sort, fn {key, direction} ->
        value_placeholder_names(key) ++ value_placeholder_names(direction)
      end)

    include_names =
      term.include
      |> Map.values()
      |> Enum.flat_map(&placeholder_names/1)

    filter_names ++ bound_names ++ order_names ++ include_names
  end

  # Returns every name the given filter clauses read, in order, as {relationships, name} pairs: the
  # compared attribute of every triple, and the one an attribute operand names beside it - the
  # alternatives of a disjunction included. An attribute of the row comes with no relationships, an
  # attribute a path reaches with the relationships followed to it. For readers that need what a
  # filter reads rather than how it compares.
  @doc false
  @spec predicate_references(list(Query.clause())) ::
          list({list(atom), atom | Query.placeholder()})
  def predicate_references(clauses) do
    clauses
    |> triples()
    |> Enum.flat_map(fn
      {name, _operator, {:attribute, other}} -> [reference(name), reference(other)]
      {name, _operator, _value} -> [reference(name)]
    end)
  end

  @doc false
  @spec predicate_triples!(module, Query.predicates()) :: list(Query.clause())
  def predicate_triples!(entity_type, predicates) do
    Enum.flat_map(predicates, fn
      {%Placeholder{name: placeholder_name}, value} ->
        [placeholder_key_triple(placeholder_name, value)]

      # The shape decides rather than the name, so or is no reserved attribute name: a list of lists
      # is no value any attribute takes - a membership list holds plain values and a list of
      # operator tuples holds tuples - and an attribute named or keeps every other spelling.
      {:or, alternatives} = entry when is_list(alternatives) ->
        if Enum.all?(alternatives, &is_list/1) do
          [disjunction!(entity_type, alternatives)]
        else
          attribute_triples!(entity_type, entry)
        end

      entry ->
        attribute_triples!(entity_type, entry)
    end)
  end

  @doc false
  @spec put_attribute(Entity.t(), keyword | map) :: Entity.t()
  def put_attribute(entity, values) when is_list(values) or is_map(values) do
    entity_type = entity_type!(entity, "put_attribute")

    if is_list(values) and not Keyword.keyword?(values) do
      raise ArgumentError,
        message:
          "put_attribute takes a keyword list or a map of attribute values, got: #{inspect(values)}"
    end

    values_map = Map.new(values)

    Enum.each(values_map, fn {name, _value} -> validate_put_name!(name, entity_type) end)

    %Metadata{attribute_ops: recorded_ops} = metadata = entity.__meta__

    # Stages apply in order: a put replaces whatever op the attribute carried - an earlier put or an
    # increment alike.
    ops =
      Enum.reduce(values_map, recorded_ops, fn {name, value}, acc ->
        Map.put(acc, name, {:put, value})
      end)

    entity
    |> Map.merge(values_map)
    |> Map.put(:__meta__, %Metadata{metadata | attribute_ops: ops})
  end

  def put_attribute(_entity, values) do
    raise ArgumentError,
      message:
        "put_attribute takes a keyword list or a map of attribute values, got: #{inspect(values)}"
  end

  @doc false
  @spec put_attribute(Entity.t(), atom, any) :: Entity.t()
  def put_attribute(entity, name, value) do
    put_attribute(entity, [{name, value}])
  end

  @doc false
  @spec sort(module | Query.t(), atom | list) :: Query.t()
  def sort(query, spec) do
    term = to_term(query)

    entries = order_entries!(spec, term.entity)

    %{term | sort: entries}
  end

  @doc false
  @spec take(module | Query.t(), non_neg_integer) :: Query.t()
  def take(query, value) do
    set_view_bound!(query, :take, value)
  end

  # Returns every predicate triple of the given filter clauses, in order, the ones inside a
  # disjunction's alternatives included.
  @doc false
  @spec triples(list(Query.clause())) :: list(Query.predicate())
  def triples(clauses) do
    Enum.flat_map(clauses, fn
      {:or, alternatives} -> Enum.flat_map(alternatives, &triples/1)
      triple -> [triple]
    end)
  end

  @doc false
  @spec trust(Entity.t() | module | Query.t()) :: Entity.t() | Query.t()
  # A query term is a struct too, so the entity-struct clause has to say which struct it means -
  # every other stage takes one or the other, and this one takes both.
  def trust(%{__struct__: entity_type} = entity) when entity_type != Query do
    put_claim(entity, :trust, "trust")
  end

  def trust(query) do
    term = to_term(query)

    %{term | trust: true}
  end

  # Returns every name the given data-form predicates spell, in order, without judging any of them:
  # each key, the name an {:attribute, name} operand carries bare or under an operator, and what the
  # lists of an or: entry spell - a path as its list. For readers of predicates no entity type was
  # asked about yet, such as the hint a build gives for a filter no entity type admits.
  @doc false
  @spec written_names(list) :: list(atom | Query.path())
  def written_names(predicates) do
    Enum.flat_map(predicates, fn
      {:or, alternatives} when is_list(alternatives) ->
        if Enum.all?(alternatives, &is_list/1) do
          Enum.flat_map(alternatives, &written_names/1)
        else
          [:or]
        end

      {name, value} when is_atom(name) ->
        [name | written_operand_names(value)]

      {name, value} when is_list(name) ->
        if path?(name), do: [name | written_operand_names(value)], else: []

      _entry ->
        []
    end)
  end

  # A path is defined where it ends, so its last name is looked up on the type its relationships
  # lead to.
  defp attribute_definition(entity_type, name) do
    {subject_type, subject_name} = subject(entity_type, name)
    definitions = subject_type.__attributes__() ++ subject_type.__system_attributes__()

    Enum.find(definitions, fn {definition_name, _type, _opts} ->
      definition_name == subject_name
    end)
  end

  defp attribute_names(entity_type) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    definitions
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.sort()
  end

  defp attribute_triple!(name, operator, other, entity_type) do
    if operator in @ordering_operators do
      validate_orderable_attribute!(name, entity_type, operator)
    end

    validate_operand_name!(other, entity_type)
    validate_comparable_attributes!(name, other, operator, entity_type)

    {name, operator, {:attribute, other}}
  end

  defp attribute_triples!(entity_type, {name, value}) do
    validate_predicate_name!(name, entity_type)

    predicate_triples!(name, value, entity_type)
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

  # A counter is an integer attribute that always holds a number: an optional one can be nil, and
  # there is nothing to add to nil.
  defp counter_attribute_names(entity_type) do
    entity_type.__attributes__()
    |> Enum.reject(fn {_name, _type, opts} -> Keyword.get(opts, :optional) == true end)
    |> integer_names()
  end

  # One alternative says what its predicates say alone, and an empty one says nothing at all - it
  # would make the disjunction hold for every row - so neither is a disjunction, and every executor
  # is spared both shapes. The lowering never produces either.
  defp disjunction!(entity_type, alternatives) do
    if length(alternatives) < 2 do
      raise ArgumentError,
        message:
          "a disjunction takes a list of at least two predicate lists, got: #{inspect(alternatives)}"
    end

    Enum.each(alternatives, fn alternative ->
      if alternative == [] or not filterable_predicates?(alternative) do
        raise ArgumentError,
          message:
            "an alternative of a disjunction is a non-empty list of name and value pairs, got: #{inspect(alternative)}"
      end
    end)

    {:or, Enum.map(alternatives, &predicate_triples!(entity_type, &1))}
  end

  # A stage on an entity struct: the struct's type, or a refusal naming the stage.
  defp entity_type!(%{__struct__: entity_type}, stage) do
    if Reflection.entity?(entity_type) do
      entity_type
    else
      raise ArgumentError,
        message: "#{stage} takes an entity struct, got: #{inspect(%{__struct__: entity_type})}"
    end
  end

  defp entity_type!(subject, stage) do
    raise ArgumentError, message: "#{stage} takes an entity struct, got: #{inspect(subject)}"
  end

  defp enum_values(entity_type, name) do
    {_name, :enum, opts} = attribute_definition(entity_type, name)

    Keyword.fetch!(opts, :values)
  end

  defp equality_triple!(name, operator, operand) do
    if is_list(operand) or is_tuple(operand) or is_struct(operand, Range) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect_name(name)}"
    end

    {name, operator, operand}
  end

  defp filterable_names(entity_type) do
    Enum.sort(attribute_names(entity_type) ++ reference_field_names(entity_type))
  end

  # Keyword.keyword?/1 with placeholder keys and paths admitted - a placeholder names an attribute
  # nobody knows yet, and a path one of a related row.
  defp filterable_predicates?(predicates) when is_list(predicates) do
    Enum.all?(predicates, fn
      {%Placeholder{}, _value} -> true
      {name, _value} when is_atom(name) -> true
      {name, _value} -> path?(name)
      _entry -> false
    end)
  end

  defp filterable_predicates?(_predicates), do: false

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

  defp integer_names(definitions) do
    definitions
    |> Enum.filter(fn {_name, type, _opts} -> type == :integer end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  # Two includes of one relationship are one include when neither narrows it: what each includes
  # merges, by the same rule all the way down. A sub-term that narrows it asks for different rows
  # than the other, so a relationship included twice with clauses on either side is refused.
  defp merged_sub_term!(included, sub_term, name) do
    if sub_term_has_clauses?(included) or sub_term_has_clauses?(sub_term) do
      raise ArgumentError,
        message: "relationship #{inspect(name)} is already included"
    end

    merged_include =
      Enum.reduce(sub_term.include, included.include, fn {nested_name, nested_sub_term}, acc ->
        put_included!(acc, nested_name, nested_sub_term)
      end)

    %{included | include: merged_include}
  end

  defp moved_value(entity, name, entity_type, delta, stage) do
    case Map.fetch!(entity, name) do
      value when is_integer(value) ->
        value + delta

      nil ->
        raise ArgumentError,
          message:
            "#{inspect(name)} in #{inspect(entity_type)} holds nil - a counter always holds a number, so there is nothing for #{stage} to move - read the row first, or give the attribute a default"
    end
  end

  defp normalize_membership_values(values) do
    Enum.map(values, fn
      %Placeholder{name: placeholder_name} -> {:placeholder, placeholder_name}
      value -> value
    end)
  end

  defp normalized_clause({:or, alternatives}) do
    sorted_alternatives =
      alternatives
      |> Enum.map(&normalized_filter/1)
      |> Enum.sort()

    {:or, sorted_alternatives}
  end

  defp normalized_clause(triple), do: triple

  defp normalized_includes(term) do
    Map.new(term.include, fn {name, sub_term} ->
      {name, normalized_sub_term(sub_term, relationship_kind(term.entity, name))}
    end)
  end

  defp normalized_order(term) do
    ordering_keys = Enum.map(term.sort, fn {name, _direction} -> name end)

    cond do
      term.cardinality == :count -> []
      :id in ordering_keys -> term.sort
      true -> List.insert_at(term.sort, -1, {:id, :asc})
    end
  end

  defp normalized_sub_term(sub_term, :to_many), do: normalized_term(sub_term)

  defp normalized_sub_term(sub_term, :to_one) do
    %{sub_term | include: normalized_includes(sub_term)}
  end

  defp normalized_term(term) do
    %{
      term
      | filter: normalized_filter(term.filter),
        include: normalized_includes(term),
        sort: normalized_order(term)
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
      message: "sort spec must be an attribute name or a list, got: #{inspect(spec)}"
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
        "invalid sort entry #{inspect(entry)} - use an attribute name or an {attribute, :asc | :desc} tuple"
  end

  defp ordering_triple!(name, operator, operand, entity_type) do
    validate_orderable_attribute!(name, entity_type, operator)

    if is_nil(operand) or is_list(operand) or is_tuple(operand) or is_struct(operand, Range) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect_name(name)}"
    end

    validate_enum_operand!(name, operand, entity_type)

    {name, operator, operand}
  end

  # The offset a page produces depends on both options, so a placeholder in either makes it one too -
  # named for whichever option it varies with, page first.
  #
  # THE NAME IS NOT A BINDING KEY. A leaf names the ARGUMENT a value derives from, never the value
  # itself, which is why `offset(^((page - 1) * size))` written out by hand yields this same leaf, and
  # why `filter(b: ^(n * 2))` yields `{:b, :==, {:placeholder, :n}}`. Nothing ever turns a leaf back
  # into a value: both tiers call the real builder with the component's real props, so the offset
  # that executes is the computed one.
  defp paginate_offset(%Placeholder{} = page, _size), do: page

  defp paginate_offset(_page, %Placeholder{} = size), do: size

  defp paginate_offset(page, size), do: (page - 1) * size

  defp path?([_hop, _name | _rest] = names), do: Enum.all?(names, &is_atom/1)

  defp path?(_name), do: false

  # Nothing about a placeholder-keyed predicate can be checked - the attribute is unknown, so its type,
  # its operators and its operand's shape are all unknown with it. The triple records what was
  # written and Hologram.Query.Window drops it from the download, the real builder validating for
  # real once the attribute arrives.
  #
  # A bare attribute operand is an equality, as it is under an attribute's own name - read as an
  # operator tuple, it would store :attribute where the operator goes.
  defp placeholder_key_triple(placeholder_name, {:attribute, _other} = operand) do
    {{:placeholder, placeholder_name}, :==, operand}
  end

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

  defp plain_value?(value) do
    not is_tuple(value) and not is_list(value) and not is_struct(value, Range)
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

  defp predicate_triples!(name, {:attribute, other}, entity_type)
       when is_atom(other) or is_list(other) do
    [attribute_triple!(name, :==, other, entity_type)]
  end

  defp predicate_triples!(name, {operator, {:attribute, other}}, entity_type)
       when (operator in @equality_operators or operator in @ordering_operators) and
              (is_atom(other) or is_list(other)) do
    [attribute_triple!(name, operator, other, entity_type)]
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
      message: "invalid filter value #{inspect(value)} for attribute #{inspect_name(name)}"
  end

  defp predicate_triples!(name, values, entity_type) when is_list(values) do
    cond do
      values == [] ->
        raise ArgumentError,
          message: "filter list for attribute #{inspect_name(name)} must not be empty"

      Enum.all?(values, &constraint_tuple?/1) ->
        Enum.flat_map(values, fn value -> predicate_triples!(name, value, entity_type) end)

      Enum.all?(values, &plain_value?/1) ->
        validate_membership_list!(values, name, :in)
        [{name, :in, normalize_membership_values(values)}]

      true ->
        raise ArgumentError,
          message:
            "invalid filter list #{inspect(values)} for attribute #{inspect_name(name)} - use either a membership list of plain values or a list of operator tuples"
    end
  end

  defp predicate_triples!(name, value, _entity_type), do: [{name, :==, value}]

  # The two claim stages share everything but the claim they record. A second claim is refused
  # here, where it is written - a struct carrying two authorities would have to pick one at the
  # write, silently.
  defp put_claim(entity, claim, stage) do
    entity_type = entity_type!(entity, stage)

    %Metadata{claim: recorded_claim} = metadata = entity.__meta__

    if recorded_claim != nil do
      raise ArgumentError,
        message:
          "#{inspect(entity_type)} already carries a claim (#{inspect(recorded_claim)}) - a write claims exactly one authority"
    end

    Map.put(entity, :__meta__, %Metadata{metadata | claim: claim})
  end

  # The two counter stages share everything but the sign they record. A sum that reaches zero is
  # dropped rather than recorded: a delta of nothing is not a change, and the wire refuses one.
  defp put_delta(entity, name, amount, sign, stage) do
    entity_type = entity_type!(entity, stage)

    validate_delta_name!(name, entity_type, stage)
    validate_amount!(amount, stage)

    %Metadata{attribute_ops: ops} = metadata = entity.__meta__

    case Map.get(ops, name) do
      # Stages apply in order: an increment after a put folds into the value, so the attribute
      # keeps one op.
      {:put, value} when is_integer(value) ->
        put_attribute(entity, name, value + sign * amount)

      {:put, value} ->
        raise ArgumentError,
          message:
            "#{inspect(name)} in #{inspect(entity_type)} carries a put value that is not an integer (#{inspect(value)}) - #{stage} cannot move it"

      recorded ->
        delta = recorded_increment(recorded) + sign * amount

        recorded_ops =
          if delta == 0, do: Map.delete(ops, name), else: Map.put(ops, name, {:increment, delta})

        # The field previews the result the way a put value does - only the recorded amount is
        # written, so the row still computes the value from whatever it holds at the write.
        entity
        |> Map.put(name, moved_value(entity, name, entity_type, sign * amount, stage))
        |> Map.put(:__meta__, %Metadata{metadata | attribute_ops: recorded_ops})
    end
  end

  defp put_included!(include, name, sub_term) do
    case Map.fetch(include, name) do
      {:ok, included} -> Map.put(include, name, merged_sub_term!(included, sub_term, name))
      :error -> Map.put(include, name, sub_term)
    end
  end

  # The two edge stages share everything but the operation they record.
  defp put_relationship_op(entity, relationship_name, target_id, op, stage) do
    entity_type = entity_type!(entity, stage)

    validate_edge_relationship_name!(relationship_name, entity_type)

    if not is_binary(target_id) do
      raise ArgumentError,
        message: "#{stage} takes a target id string, got: #{inspect(target_id)}"
    end

    %Metadata{relationship_ops: relationship_ops} = metadata = entity.__meta__

    recorded_ops = Map.put(relationship_ops, {relationship_name, target_id}, op)

    Map.put(entity, :__meta__, %Metadata{metadata | relationship_ops: recorded_ops})
  end

  defp raise_unknown_operator!(operator, name) do
    raise ArgumentError,
      message:
        "unknown operator #{inspect(operator)} in the filter predicate for attribute #{inspect_name(name)} - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"
  end

  defp recorded_increment(nil), do: 0

  defp recorded_increment({:increment, amount}), do: amount

  defp reference(path) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    {relationship_names, name}
  end

  defp reference(name), do: {[], name}

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

    Map.replace!(term, field, {:placeholder, placeholder_name})
  end

  defp set_view_bound!(query, field, value) do
    term = to_term(query)

    if not is_integer(value) or value < 0 do
      raise ArgumentError,
        message: "#{field} must be a non-negative integer, got: #{inspect(value)}"
    end

    Map.replace!(term, field, value)
  end

  defp settable_names(entity_type) do
    declared_names = Enum.map(entity_type.__attributes__(), fn {name, _type, _opts} -> name end)

    Enum.sort(declared_names ++ reference_field_names(entity_type))
  end

  defp sub_term_has_clauses?(sub_term) do
    sub_term.filter != [] or sub_term.sort != [] or sub_term.take != nil or
      sub_term.offset != nil
  end

  # Where a name is declared: an attribute on the queried type, a path's last name on the type its
  # relationships lead to. The path is validated before anything asks.
  defp subject(entity_type, name) when is_list(name) do
    {hops, [subject_name]} = Enum.split(name, -1)

    {Entity.path_target(entity_type, hops), subject_name}
  end

  defp subject(entity_type, name), do: {entity_type, name}

  defp system_attribute_names(entity_type) do
    Enum.map(entity_type.__system_attributes__(), fn {name, _type, _opts} -> name end)
  end

  defp to_many_relationship_names(entity_type) do
    entity_type.__relationships__()
    |> Enum.filter(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  defp to_one_relationship_names(entity_type) do
    entity_type.__relationships__()
    |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  defp to_term(%Query{} = term), do: term

  defp to_term(query) do
    if Reflection.entity?(query) do
      %Query{entity: query}
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
          "user_id() requires a uuid attribute - attribute #{inspect_name(name)} in #{inspect(entity_type)} has type #{inspect(type)}"
    end
  end

  # increment is the general form and takes any integer - a computed amount passes through with
  # its sign. decrement is the readable spelling for a literal move down, so an amount that is
  # not positive is refused: decrement(:stock, -1) has no sensible reading, and increment covers
  # it.
  defp validate_amount!(amount, "increment") when is_integer(amount), do: :ok

  defp validate_amount!(amount, "decrement") when is_integer(amount) and amount > 0, do: :ok

  defp validate_amount!(amount, "increment") do
    raise ArgumentError, message: "increment takes an integer amount, got: #{inspect(amount)}"
  end

  defp validate_amount!(amount, "decrement") do
    raise ArgumentError,
      message: "decrement takes a positive integer amount, got: #{inspect(amount)}"
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

  # Two attributes compare on one order and one notion of equality, so their types have to agree -
  # the same type, or a widening - and two enums have to declare the same values in the same order,
  # since a comparison reads positions. An attribute compared with itself says nothing anyone means.
  defp validate_comparable_attributes!(name, name, operator, entity_type) do
    raise ArgumentError,
      message:
        "operator #{inspect(operator)} compares attribute #{inspect_name(name)} in #{inspect(entity_type)} with itself"
  end

  defp validate_comparable_attributes!(name, other, operator, entity_type) do
    type = attribute_type(entity_type, name)
    other_type = attribute_type(entity_type, other)

    cond do
      type != other_type and {type, other_type} not in @widenings ->
        raise ArgumentError,
          message:
            "operator #{inspect(operator)} compares attribute #{inspect_name(name)} with attribute #{inspect_name(other)} in #{inspect(entity_type)}, which have different types (#{inspect(type)} and #{inspect(other_type)}) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)"

      type == :enum and enum_values(entity_type, name) != enum_values(entity_type, other) ->
        raise ArgumentError,
          message:
            "operator #{inspect(operator)} compares attribute #{inspect_name(name)} with attribute #{inspect_name(other)} in #{inspect(entity_type)}, which declare different values (#{inspect(enum_values(entity_type, name))} and #{inspect(enum_values(entity_type, other))}) - two enum attributes compare only when they declare the same values in the same order"

      true ->
        :ok
    end
  end

  defp validate_delta_name!(name, entity_type, stage) do
    counter_names = counter_attribute_names(entity_type)
    system_names = system_attribute_names(entity_type)

    cond do
      name in counter_names ->
        :ok

      name in integer_names(entity_type.__attributes__()) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} in #{inspect(entity_type)} is optional and can hold nil - #{stage} moves attributes that always hold a number - declare it without optional: true, with a default"

      name in system_names ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a system attribute of #{inspect(entity_type)} - it is managed automatically and can't be moved"

      name in attribute_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a #{inspect(attribute_type(entity_type, name))} attribute of #{inspect(entity_type)} - #{stage} moves integer attributes only"

      name in relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - #{stage} moves integer attributes only"

      true ->
        known = Enum.map_join(counter_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown attribute #{inspect(name)} in #{inspect(entity_type)} - known counters: #{known}"
    end
  end

  # A declared to-many relationship - refused where it is written, with the fix named for the
  # names an edge stage is most often given by mistake.
  defp validate_edge_relationship_name!(name, entity_type) do
    to_many_names = to_many_relationship_names(entity_type)

    cond do
      name in to_many_names ->
        :ok

      name in to_one_relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a to-one relationship in #{inspect(entity_type)} - only to-many relationships hold edges - set its reference via put_attribute(:#{name}_id, id)"

      name in attribute_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is an attribute in #{inspect(entity_type)} - only to-many relationships hold edges - put it via put_attribute"

      true ->
        known = Enum.map_join(to_many_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown relationship #{inspect(name)} in #{inspect(entity_type)} - known to-many relationships: #{known}"
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
              "#{inspect(operand)} is not a value of attribute #{inspect_name(name)} in #{inspect(entity_type)} - the values are #{inspect(values)}"
        end

      _other ->
        :ok
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

  defp validate_membership_list!(values, name, _operator) when is_list(values) do
    if values == [] do
      raise ArgumentError,
        message: "membership list for attribute #{inspect_name(name)} must not be empty"
    end

    Enum.each(values, fn
      value when is_list(value) or is_tuple(value) ->
        raise ArgumentError,
          message:
            "invalid membership list element #{inspect(value)} for attribute #{inspect_name(name)} - membership lists hold plain values"

      %Range{} = value ->
        raise ArgumentError,
          message:
            "invalid membership list element #{inspect(value)} for attribute #{inspect_name(name)} - membership lists hold plain values"

      _value ->
        :ok
    end)
  end

  defp validate_membership_list!(operand, name, operator) do
    raise ArgumentError,
      message:
        "operator #{inspect(operator)} on attribute #{inspect_name(name)} requires a list operand, got: #{inspect(operand)}"
  end

  defp validate_membership_range!(range, name, entity_type) do
    type = attribute_type(entity_type, name)

    if type != :integer do
      raise ArgumentError,
        message:
          "range #{inspect(range)} requires an integer attribute - attribute #{inspect_name(name)} in #{inspect(entity_type)} has type #{inspect(type)}"
    end

    if range.step != 1 do
      raise ArgumentError,
        message:
          "stepped range #{inspect(range)} for attribute #{inspect_name(name)} is not supported - membership ranges use step 1"
    end

    if Range.size(range) == 0 do
      raise ArgumentError,
        message:
          "range #{inspect(range)} for attribute #{inspect_name(name)} is empty - it would match nothing"
    end
  end

  # What an attribute operand names - another attribute of the row, or a path to one - refused in
  # the words a predicate's own name is.
  defp validate_operand_name!(name, entity_type) when is_atom(name) do
    validate_filtered_name!(name, entity_type)
  end

  defp validate_operand_name!(name, entity_type) do
    if not path?(name) do
      raise ArgumentError,
        message:
          "invalid attribute operand #{inspect({:attribute, name})} - an attribute is named by an atom, and a path by a list of two or more atoms"
    end

    validate_path!(name, entity_type)
  end

  defp validate_orderable_attribute!(name, entity_type, operator) do
    type = attribute_type(entity_type, name)

    if type not in @orderable_types do
      raise ArgumentError,
        message:
          "operator #{inspect(operator)} requires an orderable attribute - attribute #{inspect_name(name)} in #{inspect(entity_type)} has type #{inspect(type)}, and boolean and uuid attributes have no order to compare by"
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

  # A path is followed hop by hop from the queried type, each hop a to-one relationship of the type
  # the hops before it lead to, and its last name is filterable on the type it ends at - so every
  # refusal names the type it was asked of.
  defp validate_path!(path, entity_type) do
    {hops, [name]} = Enum.split(path, -1)

    end_type = Enum.reduce(hops, entity_type, &validate_path_hop!/2)

    validate_filtered_name!(name, end_type)
  end

  defp validate_path_hop!(hop, entity_type) do
    definitions = entity_type.__relationships__()

    case Enum.find(definitions, fn {name, _type, _opts} -> name == hop end) do
      {_name, [_target], _opts} ->
        raise ArgumentError,
          message:
            "#{inspect(hop)} is a to-many relationship in #{inspect(entity_type)} - a path in a condition goes through to-one relationships only"

      {_name, target, _opts} ->
        target

      nil ->
        if hop in attribute_names(entity_type) do
          raise ArgumentError,
            message:
              "#{inspect(hop)} is an attribute in #{inspect(entity_type)} - a path goes through relationships, and only its last name is an attribute"
        end

        known =
          entity_type
          |> relationship_names()
          |> Enum.map_join(", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown relationship #{inspect(hop)} in #{inspect(entity_type)} - known relationships: #{known}"
    end
  end

  defp validate_predicate_name!(name, entity_type) when is_atom(name) do
    validate_filtered_name!(name, entity_type)
  end

  defp validate_predicate_name!(name, entity_type), do: validate_path!(name, entity_type)

  # What DB.update/3 accepts as a change name - a declared attribute or a to-one reference field -
  # refused where it is written rather than at the write, with the fix named for the mistakes a
  # relationship invites.
  defp validate_put_name!(name, entity_type) do
    settable_names = settable_names(entity_type)

    cond do
      name in settable_names ->
        :ok

      name in to_one_relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be put - set its reference via :#{name}_id"

      name in relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be put - add its edges via add_relationship"

      name in system_attribute_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a system attribute of #{inspect(entity_type)} - it is managed automatically and can't be put"

      true ->
        known = Enum.map_join(settable_names, ", ", &inspect/1)

        raise ArgumentError,
          message:
            "unknown attribute #{inspect(name)} in #{inspect(entity_type)} - known attributes: #{known}"
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

    if sub_term.trust do
      raise ArgumentError,
        message:
          "include sub-terms take no trust mark - trust/1 goes on the query root and reads the whole query, includes and all, on the server's authority"
    end

    if kind == :to_one and sub_term_has_clauses?(sub_term) do
      raise ArgumentError,
        message:
          "to-one relationship #{inspect(name)} takes no clauses - clauses apply to to-many includes"
    end
  end

  defp validate_sub_term_entity!(%Query{entity: target}, _name, target), do: :ok

  defp validate_sub_term_entity!(%Query{entity: other_entity_type}, name, target) do
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

  defp written_operand_name(name) when is_atom(name), do: [name]

  defp written_operand_name(name), do: if(path?(name), do: [name], else: [])

  defp written_operand_names({:attribute, name}), do: written_operand_name(name)

  defp written_operand_names({_operator, {:attribute, name}}), do: written_operand_name(name)

  defp written_operand_names(_value), do: []
end
