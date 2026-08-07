defmodule Hologram.Query do
  @moduledoc false

  alias Hologram.Reflection

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
  comparison `{:<, value}`, `{:<=, value}`, `{:>, value}`, `{:>=, value}` - or a bare
  list of plain values (membership shorthand for `{:in, list}`). Each predicate becomes
  an `{attribute, operator, value}` triple, appended in the given order. A query term is
  a plain-data description of a query - building it never executes anything.

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
        validate_attribute_name!(name, term.entity)
        predicate_triples!(name, value, term.entity)
      end)

    %{term | filter: term.filter ++ triples}
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

  defp equality_triple!(name, operator, operand) do
    if is_list(operand) or is_tuple(operand) do
      raise ArgumentError,
        message:
          "invalid operand #{inspect(operand)} for operator #{inspect(operator)} on attribute #{inspect(name)}"
    end

    {name, operator, operand}
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

  defp predicate_triples!(name, values, _entity_type) when is_list(values) do
    validate_membership_list!(values, name, :in)

    [{name, :in, values}]
  end

  defp predicate_triples!(name, value, _entity_type), do: [{name, :==, value}]

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

  defp validate_attribute_name!(name, entity_type) do
    attribute_names = attribute_names(entity_type)

    cond do
      name in attribute_names ->
        :ok

      name in relationship_names(entity_type) ->
        raise ArgumentError,
          message:
            "#{inspect(name)} is a relationship in #{inspect(entity_type)} - only attributes can be filtered"

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
end
