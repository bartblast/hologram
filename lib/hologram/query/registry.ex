defmodule Hologram.Query.Registry do
  @moduledoc false

  alias Hologram.Query.Window

  @id_bytes 16

  @doc """
  Builds the query registry from the given normalized query terms - a map from
  content id to an entry holding the term, its derived param shape, the window it
  downloads and that window's id.

  The window is what a client keeps for the query, which is wider than what the
  query answers whenever a param picks among rows the client should already hold -
  see `Hologram.Query.Window`. Its id is the content id of the window term, so
  queries downloading the same rows name one window between them. Structurally equal
  terms collapse into one entry.
  """
  @spec build(list(%{atom => any})) :: %{String.t() => %{atom => any}}
  def build(terms) do
    Map.new(terms, fn term ->
      window = Window.derive(term)

      entry = %{
        param_shape: param_shape(term),
        term: term,
        window: window,
        window_id: id(window)
      }

      {id(term), entry}
    end)
  end

  @doc """
  Returns the content id of the given normalized query term - a lowercase hex string
  of the truncated SHA-256 of the term's deterministic external representation.

  Structurally equal terms share an id, across builds and machines - any change to
  the term changes it.
  """
  @spec id(%{atom => any}) :: String.t()
  def id(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, @id_bytes)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Returns the set of entity types the given normalized query term reads - its own
  and every one it includes, walked recursively.
  """
  @spec entity_types(%{atom => any}) :: MapSet.t(module)
  def entity_types(term) do
    collect_entity_types(term, MapSet.new())
  end

  @doc """
  Returns the set of {entity type, attribute name} pairs the given normalized
  query terms order by on :string attributes - the pairs whose practical ordering
  needs a derived sort-key companion. Includes are walked recursively. Attributes
  of other types order natively and yield no pairs.
  """
  @spec ordered_string_pairs(list(%{atom => any})) :: MapSet.t()
  def ordered_string_pairs(terms) do
    Enum.reduce(terms, MapSet.new(), &collect_ordered_pairs/2)
  end

  @doc """
  Derives the param shape of the given normalized query term - a map from param name
  to the logical type the param binds as.

  The term's filter predicates are walked recursively through its includes. A param
  bound as a whole membership operand binds as a list of the attribute's logical
  type - `{:list, type}` - a param as a membership list element or under any other
  operator binds the attribute's type directly. A param met several times with one
  type appears once.

  Raises Hologram.CompileError when one param name meets conflicting types.
  """
  @spec param_shape(%{atom => any}) :: %{atom => atom | {:list, atom}}
  def param_shape(term) do
    collect_params(term, %{})
  end

  # A name matching no attribute definition is a to-one reference field - every reference
  # column carries the entity id type.
  defp attribute_type(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    case Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end) do
      {_name, type, _opts} -> type
      nil -> :uuid
    end
  end

  defp collect_entity_types(term, acc) do
    term.include
    |> Map.values()
    |> Enum.reduce(MapSet.put(acc, term.entity), &collect_entity_types/2)
  end

  defp collect_ordered_pairs(term, acc) do
    acc_with_own_pairs =
      Enum.reduce(term.order_by, acc, fn {attribute_name, _direction}, inner_acc ->
        if attribute_type(term.entity, attribute_name) == :string do
          MapSet.put(inner_acc, {term.entity, attribute_name})
        else
          inner_acc
        end
      end)

    term.include
    |> Map.values()
    |> Enum.reduce(acc_with_own_pairs, &collect_ordered_pairs/2)
  end

  defp collect_param({name, operator, {:param, param_name}}, entity_type, acc) do
    base_type = attribute_type(entity_type, name)
    type = if operator in [:in, :not_in], do: {:list, base_type}, else: base_type

    collect_param_type(acc, param_name, type)
  end

  # A param as a membership list element binds a single value of the
  # attribute's type.
  defp collect_param({name, _operator, values}, entity_type, acc) when is_list(values) do
    base_type = attribute_type(entity_type, name)

    values
    |> Enum.filter(&match?({:param, _param_name}, &1))
    |> Enum.reduce(acc, fn {:param, param_name}, inner_acc ->
      collect_param_type(inner_acc, param_name, base_type)
    end)
  end

  defp collect_param(_triple, _entity_type, acc), do: acc

  defp collect_param_type(acc, param_name, type) do
    case acc do
      %{^param_name => ^type} ->
        acc

      %{^param_name => existing_type} ->
        raise Hologram.CompileError,
          message:
            "param #{inspect(param_name)} binds as #{inspect(existing_type)} and #{inspect(type)} - rename one of the conflicting variables"

      _acc ->
        Map.put(acc, param_name, type)
    end
  end

  defp collect_params(term, acc) do
    filter_acc =
      Enum.reduce(term.filter, acc, fn triple, inner_acc ->
        collect_param(triple, term.entity, inner_acc)
      end)

    Enum.reduce(term.include, filter_acc, fn {_name, sub_term}, inner_acc ->
      collect_params(sub_term, inner_acc)
    end)
  end
end
