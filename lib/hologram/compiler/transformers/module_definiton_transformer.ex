defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Expander, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition

  @empty_context %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

  def transform(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, block_before_expansion}]]} = ast
    uses = aggregate_expressions(:use, block_before_expansion, @empty_context)

    {:defmodule, _, [{:__aliases__, _, module}, [do: {:__block__, _, block_after_expansion}]]} =
      Expander.expand(ast)

    build_module(block_after_expansion, module, uses)
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
    imports = aggregate_expressions(:import, ast, @empty_context)
    aliases = aggregate_expressions(:alias, ast, @empty_context)
    attributes = aggregate_expressions(:@, ast, @empty_context)

    context = %Context{
      module: module,
      uses: uses,
      imports: imports,
      aliases: aliases,
      attributes: attributes
    }

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
