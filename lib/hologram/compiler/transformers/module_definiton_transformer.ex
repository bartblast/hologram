defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Expander
  alias Hologram.Compiler.Transformer

  def transform(ast) do
    {:defmodule, _, [{:__aliases__, _, module}, [do: {:__block__, _, block}]]} = ast
    uses = aggregate_expressions(:use, block, [])

    {:defmodule, _, [{:__aliases__, _, module}, [do: {:__block__, _, block}]]} =
      Expander.expand(ast)

    build_module(block, module, uses)
  end

  defp aggregate_expressions(type, ast, context) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {^type, _, _} ->
          acc ++ [Transformer.transform(expr, context)]

        _ ->
          acc
      end
    end)
  end

  defp build_module(ast, module, uses) do
    imports = aggregate_expressions(:import, ast, [])
    aliases = aggregate_expressions(:alias, ast, [])
    attributes = aggregate_expressions(:@, ast, [])

    context = [module: module, uses: uses, imports: imports, aliases: aliases, attributes: attributes]
    functions = aggregate_expressions(:def, ast, context)

    %ModuleDefinition{
      name: module,
      uses: uses,
      imports: imports,
      aliases: aliases,
      attributes: attributes,
      functions: functions
    }
  end
end
