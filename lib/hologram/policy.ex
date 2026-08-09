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
      Enum.each(entity_type.__policies__(), fn {action, to, _via, predicates} ->
        validate_to!(entity_type, action, to)
        validate_predicates!(entity_type, action, predicates)
      end)
    end)
  end

  defp to_value_valid?(value) when is_atom(value), do: true

  defp to_value_valid?([_first_role | _later_roles] = value), do: Enum.all?(value, &is_atom/1)

  defp to_value_valid?(_value), do: false

  defp validate_predicates!(entity_type, action, predicates) do
    Query.predicate_triples!(entity_type, predicates)

    :ok
  rescue
    error in ArgumentError ->
      message =
        "invalid predicate for allow #{inspect(action)} in #{inspect(entity_type)} - #{Exception.message(error)}"

      reraise Hologram.CompileError, [message: message], __STACKTRACE__
  end

  defp validate_to!(_entity_type, _action, nil), do: :ok

  defp validate_to!(entity_type, action, to) do
    if not to_value_valid?(to) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect(to)} for allow #{inspect(action)} in #{inspect(entity_type)} - the to option must be a role name or a non-empty list of role names"
    end

    declared_names = Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)

    to
    |> List.wrap()
    |> Enum.each(&validate_to_role!(entity_type, action, &1, declared_names))
  end

  defp validate_to_role!(entity_type, action, role_name, declared_names) do
    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
  end
end
