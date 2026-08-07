defmodule Hologram.Query do
  @moduledoc false

  alias Hologram.Reflection

  @directions [:asc, :desc]
  @equality_operators [:!=, :==]
  @membership_operators [:in, :not_in]
  @orderable_types [:date, :datetime, :float, :integer]
  @ordering_operators [:<, :<=, :>, :>=]

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

  Ordering comparisons require a numeric or temporal attribute (date, datetime, float,
  integer) and a non-nil operand - SQL comparisons with NULL never match, so a nil
  operand would mean different things on the two execution tiers.

  An integer Range value (`3..10`, bare or as `{:in, range}`) is shorthand for the
  inclusive bounds - it expands into a `>=` triple and a `<=` triple. Ranges require
  an integer attribute, step 1, and at least one element.

  Membership lists must be non-empty lists of plain values. They must not hold nil -
  SQL membership never matches NULL, so a nil element would mean different things on
  the two execution tiers - matching nil is an equality predicate instead.

  Raises ArgumentError when the query is neither an entity type module nor a query term,
  when the predicates are not a keyword list, when a predicate names a relationship or
  an unknown attribute, or when a predicate value is invalid (unknown operator, invalid
  membership list, list or tuple operand for an equality operator).
  """
  @spec filter(module | %{atom => any}, keyword) :: %{atom => any}
  def filter(query, predicates) do
    term = to_term(query)

    if not Keyword.keyword?(predicates) do
      raise ArgumentError,
        message: "filter predicates must be a keyword list, got: #{inspect(predicates)}"
    end

    triples =
      Enum.flat_map(predicates, fn {name, value} ->
        validate_attribute_name!(name, term.entity, "filtered")
        predicate_triples!(name, value, term.entity)
      end)

    %{term | filter: term.filter ++ triples}
  end

  @doc """
  Appends ordering keys to the given query's order list and returns the resulting
  query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. The spec is an attribute name (ascending), or a list whose entries are
  attribute names (ascending) or `{attribute, :asc | :desc}` tuples - keyword syntax
  reads naturally (`order_by(query, title: :desc)`). Each entry becomes an
  `{attribute, direction}` pair, appended in the given order, accumulating across calls.

  Ordering by enum attributes is not supported - the two execution tiers disagree on
  enum order (PostgreSQL uses declaration order, the client would use term order).

  Raises ArgumentError when the query is neither an entity type module nor a query
  term, when the spec is neither an attribute name nor a list, when an entry names a
  relationship or an unknown attribute or an enum attribute, or when a direction is
  neither :asc nor :desc.
  """
  @spec order_by(module | %{atom => any}, atom | list) :: %{atom => any}
  def order_by(query, spec) do
    term = to_term(query)

    entries = order_entries!(spec, term.entity)

    %{term | order_by: term.order_by ++ entries}
  end

  defp attribute_names(entity_type) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    definitions
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.sort()
  end

  defp attribute_type(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    {_name, type, _opts} =
      Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end)

    type
  end

  defp constraint_tuple?(value) do
    is_tuple(value) and tuple_size(value) == 2 and is_atom(elem(value, 0))
  end

  defp equality_triple!(name, operator, operand) do
    if is_list(operand) or is_tuple(operand) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect(name)}"
    end

    {name, operator, operand}
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

  defp order_entry!({name, direction}, entity_type) when is_atom(name) do
    validate_ordered_attribute!(name, entity_type)

    if direction not in @directions do
      raise ArgumentError,
        message:
          "invalid direction #{inspect(direction)} for attribute #{inspect(name)} - use :asc or :desc"
    end

    {name, direction}
  end

  defp order_entry!(name, entity_type) when is_atom(name) do
    validate_ordered_attribute!(name, entity_type)

    {name, :asc}
  end

  defp order_entry!(entry, _entity_type) do
    raise ArgumentError,
      message:
        "invalid order_by entry #{inspect(entry)} - use an attribute name or an {attribute, :asc | :desc} tuple"
  end

  defp ordering_triple!(name, operator, operand, entity_type) do
    validate_orderable_attribute!(name, entity_type, operator)

    if is_nil(operand) or is_list(operand) or is_tuple(operand) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect(name)}"
    end

    {name, operator, operand}
  end

  defp predicate_triples!(name, {:in, %Range{} = range}, entity_type) do
    predicate_triples!(name, range, entity_type)
  end

  defp predicate_triples!(name, %Range{} = range, entity_type) do
    validate_membership_range!(range, name, entity_type)

    [{name, :>=, range.first}, {name, :<=, range.last}]
  end

  defp predicate_triples!(name, {operator, operand}, entity_type) when is_atom(operator) do
    cond do
      operator in @equality_operators ->
        [equality_triple!(name, operator, operand)]

      operator in @membership_operators ->
        validate_membership_list!(operand, name, operator)
        [{name, operator, operand}]

      operator in @ordering_operators ->
        [ordering_triple!(name, operator, operand, entity_type)]

      true ->
        raise ArgumentError,
          message:
            "unknown operator #{inspect(operator)} in the filter predicate for attribute #{inspect(name)} - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"
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
        [{name, :in, values}]

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

  defp relationship_names(entity_type) do
    Enum.map(entity_type.__relationships__(), fn {name, _type, _opts} -> name end)
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

  defp validate_membership_list!(values, name, _operator) when is_list(values) do
    if values == [] do
      raise ArgumentError,
        message: "membership list for attribute #{inspect(name)} must not be empty"
    end

    Enum.each(values, fn
      nil ->
        raise ArgumentError,
          message:
            "nil in the membership list for attribute #{inspect(name)} - use an equality predicate to match nil"

      value when is_list(value) or is_tuple(value) ->
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
          "operator #{inspect(operator)} requires a numeric or temporal attribute - attribute #{inspect(name)} in #{inspect(entity_type)} has type #{inspect(type)}"
    end
  end

  defp validate_ordered_attribute!(name, entity_type) do
    validate_attribute_name!(name, entity_type, "ordered")

    if attribute_type(entity_type, name) == :enum do
      raise ArgumentError,
        message:
          "ordering by enum attributes is not supported - attribute #{inspect(name)} in #{inspect(entity_type)} has type :enum"
    end
  end
end
