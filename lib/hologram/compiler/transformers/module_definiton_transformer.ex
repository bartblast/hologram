defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer, UseDirectiveExpander}
  alias Hologram.Compiler.IR.ModuleDefinition

  def transform(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, exprs}]]} = ast
    uses = aggregate_expressions(:use, exprs, %Context{})

    {:defmodule, _, [{:__aliases__, _, module_segs}, [do: {:__block__, _, exprs}]]} =
      UseDirectiveExpander.expand(ast)

    build_module(exprs, module_segs, uses)
  end

  defp aggregate_expressions(type, exprs, context) do
    Enum.reduce(exprs, [], fn expr, acc ->
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
    macros = aggregate_expressions(:defmacro, ast, %Context{})

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
      |> Map.put(:macros, macros)

    struct(ModuleDefinition, fields)
  end
end
