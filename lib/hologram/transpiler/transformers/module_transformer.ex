defmodule Hologram.Transpiler.ModuleTransformer do
  alias Hologram.Transpiler.AST.Module
  alias Hologram.Transpiler.Expander
  alias Hologram.Transpiler.Transformer

  def transform(ast) do
    {:defmodule, _, [{:__aliases__, _, name}, [do: {:__block__, _, block}]]} =
      Expander.expand(ast)

    build_module(block, name)
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

  defp aggregate_functions(ast, module, imports, aliases) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:def, _, _} ->
          acc ++ [Transformer.transform(expr, module, imports, aliases)]

        _ ->
          acc
      end
    end)
  end

  defp build_module(ast, name) do
    imports = aggregate_directives(ast, :import)
    aliases = aggregate_directives(ast, :alias)
    functions = aggregate_functions(ast, name, imports, aliases)

    %Module{name: name, imports: imports, aliases: aliases, functions: functions}
  end
end
