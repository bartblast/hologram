defmodule Hologram.Query do
  @moduledoc false

  alias Hologram.Reflection

  @doc """
  Appends equality predicates to the given query's filter list and returns the resulting
  query term.

  The query is an entity type module (starting a fresh query term) or an already built
  query term. Predicates are a keyword list of attribute names (declared or system) and
  the values the attributes must equal - each becomes an `{attribute, :==, value}` triple,
  appended in the given order. A query term is a plain-data description of a query -
  building it never executes anything.

  Raises ArgumentError when the query is neither an entity type module nor a query term,
  when the predicates are not a keyword list, when a predicate names a relationship, or
  when a predicate names an unknown attribute.
  """
  @spec filter(module | %{atom => any}, keyword) :: %{atom => any}
  def filter(query, predicates) do
    term = to_term(query)

    if not Keyword.keyword?(predicates) do
      raise ArgumentError,
        message: "filter predicates must be a keyword list, got: #{inspect(predicates)}"
    end

    Enum.each(predicates, fn {name, _value} ->
      validate_attribute_name!(name, term.entity)
    end)

    equality_triples = Enum.map(predicates, fn {name, value} -> {name, :==, value} end)

    %{term | filter: term.filter ++ equality_triples}
  end

  defp attribute_names(entity_type) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    definitions
    |> Enum.map(fn {name, _type, _opts} -> name end)
    |> Enum.sort()
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
end
