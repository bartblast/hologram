defmodule Hologram.Compiler.ForExpressionTransformer do
  alias Hologram.Compiler.{Reflection, Transformer}

  def transform({:for, _, parts}) do
    generators = find_generators(parts)
    mapper = find_mapper(parts)

    build_code(generators, mapper)
    |> Reflection.ast()
    |> Transformer.transform()
  end

  defp build_code([generator | rest_of_generators], mapper) do
    {:<-, _, [pattern, values]} = generator

    """
    Enum.reduce(#{Macro.to_string(values)}, [], fn holo__, acc ->
    #{Macro.to_string(pattern)} = holo__
    acc ++ #{build_code(rest_of_generators, mapper)}
    end)
    """
  end

  defp build_code([], mapper) do
    [do: {:__block__, _, [mapper_ast]}] = mapper
    "[#{Macro.to_string(mapper_ast)}]"
  end

  defp find_generators(parts) do
    Enum.filter(parts, fn part ->
      match?({:<-, _, _}, part)
    end)
  end

  defp find_mapper(parts) do
    List.last(parts)
  end
end
