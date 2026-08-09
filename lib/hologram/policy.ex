defmodule Hologram.Policy do
  @moduledoc false

  alias Hologram.Query
  alias Hologram.Reflection

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

  defp declared_role_names(entity_type) do
    Enum.map(entity_type.__roles__(), fn {name, _opts} -> name end)
  end

  defp to_reference_valid?(value) when is_atom(value), do: true

  defp to_reference_valid?({target_type, role_name}) when is_atom(role_name),
    do: Reflection.alias?(target_type)

  defp to_reference_valid?(_value), do: false

  defp to_value_valid?([_first_reference | _later_references] = value),
    do: Enum.all?(value, &to_reference_valid?/1)

  defp to_value_valid?(value), do: to_reference_valid?(value)

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
          "invalid to option #{inspect(to)} for allow #{inspect(action)} in #{inspect(entity_type)} - the to option must be a role name, a {module, role} tuple, or a non-empty list of them"
    end

    to
    |> List.wrap()
    |> Enum.each(&validate_to_reference!(entity_type, action, &1))
  end

  defp validate_to_reference!(entity_type, action, {target_type, role_name}) do
    if not Reflection.entity?(target_type) do
      raise Hologram.CompileError,
        message:
          "invalid to option #{inspect({target_type, role_name})} for allow #{inspect(action)} in #{inspect(entity_type)} - #{inspect(target_type)} is not an entity type module"
    end

    declared_names = declared_role_names(target_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared roles of #{inspect(target_type)} are: #{declared_roles}"
    end
  end

  defp validate_to_reference!(entity_type, action, role_name) do
    declared_names = declared_role_names(entity_type)

    if role_name not in declared_names do
      declared_roles = Enum.map_join(declared_names, ", ", &inspect/1)

      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in the to option of allow #{inspect(action)} in #{inspect(entity_type)} - declared roles are: #{declared_roles}"
    end
  end
end
