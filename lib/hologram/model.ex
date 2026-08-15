defmodule Hologram.Model do
  @moduledoc false

  # The identity of the compiled data model - the fact a client's bundle and a written row
  # both carry, so the server can tell whether they describe the same shapes it runs now.

  alias Hologram.Reflection

  @hash_bytes 16

  @doc """
  Returns the hash identifying the project's compiled data model.
  """
  @spec hash() :: String.t()
  def hash do
    hash(Reflection.list_entities())
  end

  @doc """
  Returns the hash identifying the data model made of the given entity types - a lowercase hex
  string of the truncated SHA-256 of the model's deterministic external representation.

  The hash covers what a client can observe: each entity type's name, its declared attributes and
  relationships with their full option lists, and its system attributes. Entity types and their
  members are sorted, so the same model hashes the same however it was discovered.

  Policies and role declarations are excluded - they govern who may see a row and who is granted
  what, which the server answers on its own, rather than the shape of the data itself. Facts the
  grant store carries reach the hash through it: the app's role names and entity type names are
  its enum values, and the designated user entity type is the target of its relationships.
  """
  @spec hash(list(module)) :: String.t()
  def hash(entity_types) do
    entity_types
    |> Enum.map(&canonical_form/1)
    |> Enum.sort()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, @hash_bytes)
    |> Base.encode16(case: :lower)
  end

  defp canonical_form(entity_type) do
    canonicalize(%{
      attributes: Enum.sort(entity_type.__attributes__()),
      name: to_string(entity_type),
      relationships: Enum.sort(entity_type.__relationships__()),
      system_attributes: Enum.sort(entity_type.__system_attributes__())
    })
  end

  # A regex declared as an attribute option carries a compiled pattern that differs from one read
  # of the definition to the next, so a form holding one hashes differently every time it is
  # built. What the model declares is the pattern itself, which is what the form keeps.
  defp canonicalize(%Regex{} = regex) do
    {:regex, Regex.source(regex), Regex.opts(regex)}
  end

  defp canonicalize(%_struct{} = struct) do
    struct
  end

  defp canonicalize(term) when is_list(term) do
    Enum.map(term, &canonicalize/1)
  end

  # Any term can key a map, so the walk covers keys as well as values.
  defp canonicalize(term) when is_map(term) do
    Map.new(term, fn {key, value} -> {canonicalize(key), canonicalize(value)} end)
  end

  defp canonicalize(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.map(&canonicalize/1)
    |> List.to_tuple()
  end

  defp canonicalize(term) do
    term
  end
end
