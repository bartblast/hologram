defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer, UseDirectiveExpander}
  alias Hologram.Compiler.IR.ModuleDefinition

  def transform(ast) do
    uses = aggregate_use_expressions(ast)

    UseDirectiveExpander.expand(ast)
    |> build_module(uses)
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

  defp aggregate_use_expressions(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, exprs}]]} = ast
    aggregate_expressions(:use, exprs, %Context{})
  end

  defp build_module(ast, uses) do
    {:defmodule, _, [{:__aliases__, _, module_segs}, [do: {:__block__, _, exprs}]]} = ast

    module = Helpers.module(module_segs)
    imports = aggregate_expressions(:import, exprs, %Context{})
    requires = aggregate_expressions(:require, exprs, %Context{})
    aliases = aggregate_expressions(:alias, exprs, %Context{})
    attributes = aggregate_expressions(:@, exprs, %Context{})
    macros = aggregate_expressions(:defmacro, exprs, %Context{})

    context = %Context{
      module: module,
      uses: uses,
      imports: imports,
      requires: requires,
      aliases: aliases,
      attributes: attributes
    }

    functions = aggregate_expressions(:def, exprs, context)

    fields =
      Map.from_struct(context)
      |> Map.put(:functions, functions)
      |> Map.put(:macros, macros)

    struct(ModuleDefinition, fields)
  end
end
