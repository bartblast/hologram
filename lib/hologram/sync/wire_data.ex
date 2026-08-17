defmodule Hologram.Sync.WireData do
  @moduledoc false

  # Entity values as a sync frame carries them: plain JSON, not the JavaScript source every other
  # chunk on that stream is written in.
  #
  # What a delta can hold is closed - an attribute is a value Postgres stores, a reference is an
  # id - so the general encoder's ability to spell any term at all buys nothing here and costs a
  # great deal: a row runs about ten times the bytes as source, on the payload an app-wide fill
  # sends most of. The same values written the way the database codec already writes them are
  # small, and the client reads them with JSON.parse rather than evaluating them.
  #
  # A value the client may not have is spelled by ITS KEY BEING ABSENT, and so is a relationship
  # the query did not ask for. The three cases cannot be confused, which is what makes absence
  # safe to read: an attribute is always there (null when it is unset), a server-only attribute
  # never is, and a relationship is there exactly when the window includes it.
  #
  # Server-only attributes are dropped by what the MODEL DECLARES, never by finding a sentinel in
  # the row: a row read through the trusted tier holds the real value, and one written moments ago
  # holds what was written. Reading the row would hide the value exactly when it was already safe
  # and hand it over the rest of the time.

  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded

  @doc """
  Returns the given changed attributes of the given entity type, as a frame carries them.

  The type comes alongside because a bag of changes does not say what it belongs to, where a row
  says so itself.
  """
  @spec patch(module, map) :: map
  def patch(entity_type, data) do
    encode_fields(data, entity_type)
  end

  @doc """
  Returns the given entity row as a frame carries it.

  An included relationship travels as the rows it holds - a list for a to-many, one row or null
  for a to-one - each of them written the same way, so a server-only value stays hidden however
  deep it sits.
  """
  @spec row(struct) :: map
  def row(%entity_type{} = entity) do
    entity
    |> Map.from_struct()
    |> encode_fields(entity_type)
  end

  # System attributes are attributes here: a client is told the id and the stamps like anything
  # else. A name matching no definition is a to-one reference field, and every one of those
  # carries an entity id - the same fallback the effect log makes.
  defp attribute_types(entity_type) do
    entity_type.__attributes__()
    |> Enum.concat(entity_type.__system_attributes__())
    |> Map.new(fn {name, type, _opts} -> {name, type} end)
  end

  defp encode_field({_name, %NotIncluded{}}, _model), do: []

  defp encode_field({name, value}, model) do
    cond do
      MapSet.member?(model.server_only, name) -> []
      Map.has_key?(model.relationships, name) -> [{name, embed(value)}]
      true -> [{name, Codec.encode_json(value, Map.get(model.attribute_types, name, :uuid))}]
    end
  end

  defp encode_fields(fields, entity_type) do
    model = %{
      attribute_types: attribute_types(entity_type),
      relationships: relationships(entity_type),
      server_only: server_only(entity_type)
    }

    fields
    |> Enum.flat_map(&encode_field(&1, model))
    |> Map.new()
  end

  defp embed(nil), do: nil

  defp embed(rows) when is_list(rows), do: Enum.map(rows, &row/1)

  defp embed(row), do: row(row)

  defp server_only(entity_type) do
    entity_type
    |> Entity.server_only_attribute_names()
    |> MapSet.new()
  end

  defp relationships(entity_type) do
    Map.new(entity_type.__relationships__(), fn {name, type, _opts} -> {name, type} end)
  end
end
