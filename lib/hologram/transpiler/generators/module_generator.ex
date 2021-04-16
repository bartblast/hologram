defmodule Hologram.Transpiler.Generators.ModuleGenerator do
  alias Hologram.Transpiler.AST.Function
  alias Hologram.Transpiler.Generators.FunctionGenerator
  alias Hologram.Transpiler.Helpers

  def generate(ast, name) do
    functions =
      aggregate_functions(ast)
      |> Enum.map(fn {k, v} -> FunctionGenerator.generate(k, v) end)
      |> Enum.join("\n")

    """
    class #{Helpers.class_name(name)} {

    #{functions}
    }
    """
  end

  defp aggregate_functions(module) do
    Enum.reduce(module.functions, %{}, fn expr, acc ->
      case expr do
        %Function{name: name} = fun ->
          if Map.has_key?(acc, name) do
            Map.put(acc, name, acc[name] ++ [fun])
          else
            Map.put(acc, name, [fun])
          end
        # TODO: determine what's this case for, comment and test it
        _ ->
          acc
      end
    end)
  end
end
