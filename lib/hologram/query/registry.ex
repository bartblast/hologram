defmodule Hologram.Query.Registry do
  @moduledoc false

  alias Hologram.Query.Window

  @id_bytes 16

  @doc """
  Builds the query registry from the given normalized query terms - a map from
  content id to an entry holding the term, its derived placeholder shape, the window it
  downloads and that window's id.

  The window is what a client keeps for the query, which is wider than what the
  query answers whenever a placeholder picks among rows the client should already hold -
  see `Hologram.Query.Window`. Its id is the content id of the window term, so
  queries downloading the same rows name one window between them. Structurally equal
  terms collapse into one entry.
  """
  @spec build(list(%{atom => any})) :: %{String.t() => %{atom => any}}
  def build(terms) do
    Map.new(terms, fn term ->
      window = Window.derive(term)

      entry = %{
        placeholder_shape: placeholder_shape(term),
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
  Derives the placeholder shape of the given normalized query term - a map from placeholder name
  to the logical type the placeholder binds as.

  The term's filter predicates are walked recursively through its includes. A placeholder
  bound as a whole membership operand binds as a list of the attribute's logical
  type - `{:list, type}` - a placeholder as a membership list element or under any other
  operator binds the attribute's type directly. A placeholder met several times with one
  type appears once.

  Raises Hologram.CompileError when one placeholder name meets conflicting types.
  """
  @spec placeholder_shape(%{atom => any}) :: %{atom => atom | {:list, atom}}
  def placeholder_shape(term) do
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

  # A triple keyed by a placeholder contributes no shape: the attribute is unknown, so its type is
  # unknown with it, and attribute_type/2's :uuid fallback (which exists for reference fields) would
  # otherwise record a lie - and collide with the same placeholder's real type elsewhere, refusing a
  # legitimate query. The same reason Hologram.Query.Window drops such a predicate.
  defp collect_placeholder({{:placeholder, _key_name}, _operator, _value}, _entity_type, acc),
    do: acc

  defp collect_placeholder({name, operator, {:placeholder, placeholder_name}}, entity_type, acc) do
    base_type = attribute_type(entity_type, name)
    type = if operator in [:in, :not_in], do: {:list, base_type}, else: base_type

    collect_placeholder_type(acc, placeholder_name, type)
  end

  # A placeholder as a membership list element binds a single value of the
  # attribute's type.
  defp collect_placeholder({name, _operator, values}, entity_type, acc) when is_list(values) do
    base_type = attribute_type(entity_type, name)

    values
    |> Enum.filter(&match?({:placeholder, _placeholder_name}, &1))
    |> Enum.reduce(acc, fn {:placeholder, placeholder_name}, inner_acc ->
      collect_placeholder_type(inner_acc, placeholder_name, base_type)
    end)
  end

  defp collect_placeholder(_triple, _entity_type, acc), do: acc

  defp collect_placeholder_type(acc, placeholder_name, type) do
    case acc do
      %{^placeholder_name => ^type} ->
        acc

      %{^placeholder_name => existing_type} ->
        raise Hologram.CompileError,
          message:
            "placeholder #{inspect(placeholder_name)} binds as #{inspect(existing_type)} and #{inspect(type)} - rename one of the conflicting variables"

      _acc ->
        Map.put(acc, placeholder_name, type)
    end
  end

  defp collect_params(term, acc) do
    filter_acc =
      Enum.reduce(term.filter, acc, fn triple, inner_acc ->
        collect_placeholder(triple, term.entity, inner_acc)
      end)

    Enum.reduce(term.include, filter_acc, fn {_name, sub_term}, inner_acc ->
      collect_params(sub_term, inner_acc)
    end)
  end
end
