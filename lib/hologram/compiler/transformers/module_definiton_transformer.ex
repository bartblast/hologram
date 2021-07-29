defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Expander, Helpers, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition

  def transform(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, block_before_expansion}]]} = ast
    uses = aggregate_expressions(:use, block_before_expansion, %Context{})

    {:defmodule, _, [{:__aliases__, _, module_segs}, [do: {:__block__, _, block_after_expansion}]]} =
      Expander.expand(ast)

    build_module(block_after_expansion, module_segs, uses)
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

  defp build_module(ast, module_segs, uses) do
    module = Helpers.module(module_segs)
    imports = aggregate_expressions(:import, ast, %Context{})
    requires = aggregate_expressions(:require, ast, %Context{})
    aliases = aggregate_expressions(:alias, ast, %Context{})
    attributes = aggregate_expressions(:@, ast, %Context{})

    context = %Context{
      module: module,
      uses: uses,
      imports: imports,
      requires: requires,
      aliases: aliases,
      attributes: attributes
    }

    functions = aggregate_expressions(:def, ast, context)

    fields =
      Map.from_struct(context)
      |> Map.put(:functions, functions)

    struct(ModuleDefinition, fields)
  end
end
