defmodule Hologram.Compiler.ModuleDefinitionGenerator do
  alias Hologram.Compiler.{Context, FunctionDefinitionGenerator, Helpers}

  def generate(ir, module, %Context{} = context) do
    class = Helpers.class_name(module)

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context) end)
      |> Enum.join("\n")

    """
    window.#{class} = class #{class} {

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
