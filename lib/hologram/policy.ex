defmodule Hologram.Policy do
  @moduledoc false

  alias Hologram.Query

  @doc """
  Validates the policy declarations of the given entity type modules as a whole.

  Returns :ok, or raises Hologram.CompileError naming the first invalid declaration.
  Policy declarations are checked here rather than when they are declared, because they are validated against compiled reflection - neither the declaring module nor the entity types it references are compiled while its body is executing.
  """
  @spec validate_model!(list(module)) :: :ok
  def validate_model!(entity_types) do
    Enum.each(entity_types, fn entity_type ->
      Enum.each(entity_type.__policies__(), fn {action, _to, _via, predicates} ->
        validate_predicates!(entity_type, action, predicates)
      end)
    end)
  end

  defp validate_predicates!(entity_type, action, predicates) do
    Query.predicate_triples!(entity_type, predicates)

    :ok
  rescue
    error in ArgumentError ->
      message =
        "invalid predicate for allow #{inspect(action)} in #{inspect(entity_type)} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end
end
