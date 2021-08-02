defmodule Hologram.Compiler.ModuleDefinitionGenerator do
  alias Hologram.Compiler.{Context, FunctionDefinitionGenerator, Helpers, Opts}

  def generate(ir, module, %Context{} = context, %Opts{} = opts) do
    class = Helpers.class_name(module)

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context, opts) end)
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
