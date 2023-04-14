defmodule Hologram.Compiler.Transformer do
  import Hologram.Compiler.Macros, only: [transform: 2]

  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Reflection

  # --- CONTROL FLOW ---

  transform({:for, _, parts}) do
    generators = find_for_expression_generators(parts)
    mapper = find_for_expression_mapper(parts)

    generators
    |> rewrite_for_expression_code(mapper)
    |> Reflection.ast()
    |> transform()
  end

  # --- HELPERS ---

  defp find_for_expression_generators(parts) do
    Enum.filter(parts, fn part ->
      match?({:<-, _, _}, part)
    end)
  end

  defp find_for_expression_mapper(parts) do
    List.last(parts)
  end

  defp prepend_case_condition_access(binding) do
    %{binding | access_path: [%IR.CaseConditionAccess{} | binding.access_path]}
  end

  defp rewrite_for_expression_code([generator | rest_of_generators], mapper) do
    {:<-, _, [pattern, elems]} = generator

    """
    Enum.reduce(#{Macro.to_string(elems)}, [], fn holo_el__, holo_acc__ ->
    #{Macro.to_string(pattern)} = holo_el__
    holo_acc__ ++ #{rewrite_for_expression_code(rest_of_generators, mapper)}
    end)
    """
  end

  defp rewrite_for_expression_code([], mapper) do
    [do: {:__block__, _, [mapper_expr]}] = mapper
    "[#{Macro.to_string(mapper_expr)}]"
  end
end
