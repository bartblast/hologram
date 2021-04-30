defmodule Hologram.Transpiler.ModuleTransformer do
  alias Hologram.Transpiler.AST.Module
  alias Hologram.Transpiler.Expander
  alias Hologram.Transpiler.Transformer

  def transform(ast) do
    {:defmodule, _, [{:__aliases__, _, module}, [do: {:__block__, _, block}]]} =
      Expander.expand(ast)

    build_module(block, module)
  end

  defp aggregate_directives(ast, type) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {^type, _, _} ->
          acc ++ [Transformer.transform(expr)]

        _ ->
          acc
      end
    end)
  end

  defp aggregate_functions(ast, context) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:def, _, _} ->
          acc ++ [Transformer.transform(expr, context)]

        _ ->
          acc
      end
    end)
  end

  defp build_module(ast, module) do
    imports = aggregate_directives(ast, :import)
    aliases = aggregate_directives(ast, :alias)
    context = [module: module, imports: imports, aliases: aliases]

    functions = aggregate_functions(ast, context)

    %Module{name: module, imports: imports, aliases: aliases, functions: functions}
  end
end
