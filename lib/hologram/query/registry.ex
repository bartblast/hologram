defmodule Hologram.Query.Registry do
  @moduledoc false

  @doc """
  Derives the param shape of the given normalized query term - a map from param name
  to the logical type the param binds as.

  The term's filter predicates are walked recursively through its includes. A param
  bound by a membership operator binds as a list of the attribute's logical type -
  `{:list, type}` - any other operator binds the attribute's type directly. A param
  met several times with one type appears once.

  Raises Hologram.CompileError when one param name meets conflicting types.
  """
  @spec param_shape(%{atom => any}) :: %{atom => atom | {:list, atom}}
  def param_shape(term) do
    collect_params(term, %{})
  end

  defp attribute_type(entity_type, name) do
    definitions = entity_type.__attributes__() ++ entity_type.__system_attributes__()

    {_name, type, _opts} =
      Enum.find(definitions, fn {definition_name, _type, _opts} -> definition_name == name end)

    type
  end

  defp collect_param({name, operator, {:param, param_name}}, entity_type, acc) do
    base_type = attribute_type(entity_type, name)
    type = if operator in [:in, :not_in], do: {:list, base_type}, else: base_type

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

  defp collect_param(_triple, _entity_type, acc), do: acc

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
