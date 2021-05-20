defmodule Hologram.Compiler.ModuleDefinitionGenerator do
  alias Hologram.Compiler.IR.FunctionDefinition
  alias Hologram.Compiler.{FunctionDefinitionGenerator, Helpers}

  def generate(ir, name) do
    context = [class_name: Helpers.class_name(name)]

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context) end)
      |> Enum.join("\n")

    """
    class #{context[:class_name]} {

    #{functions}
    }
    """
  end

  defp aggregate_functions(module) do
    Enum.reduce(module.functions, %{}, fn fun, acc ->
      if Map.has_key?(acc, fun.name) do
        Map.put(acc, fun.name, acc[fun.name] ++ [fun])
      else
        Map.put(acc, fun.name, [fun])
      end
    end)
  end
end
