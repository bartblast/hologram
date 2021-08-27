defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Expander, Helpers, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition

  def transform(ast) do
    exprs = fetch_module_body(ast)
    uses = aggregate_expressions(:use, exprs, %Context{})

    ast = Expander.expand_use_directives(ast)
    exprs = fetch_module_body(ast)
    requires = aggregate_expressions(:require, exprs, %Context{})

    Expander.expand_macros(ast, requires)
    |> Expander.expand_module_pseudo_variable()
    |> build_module(uses, requires)
  end

  defp aggregate_expressions(type, exprs, context) do
    Enum.reduce(exprs, [], fn expr, acc ->
      case expr do
        {^type, _, _} ->
          ir = Transformer.transform(expr, context)
          # multi-alias is returned as a list of alias structs
          # DEFER: always return a list of alias structs
          ir = if is_list(ir), do: ir, else: [ir]
          acc ++ ir

        _ ->
          acc
      end
    end)
  end

  defp build_module(ast, uses, requires) do
    {:defmodule, _, [{:__aliases__, _, module_segs}, [do: {:__block__, _, exprs}]]} = ast

    module = Helpers.module(module_segs)
    imports = aggregate_expressions(:import, exprs, %Context{})
    aliases = aggregate_expressions(:alias, exprs, %Context{})
    attributes = aggregate_expressions(:@, exprs, %Context{})
    macros = aggregate_expressions(:defmacro, exprs, %Context{module: module})

    context = %Context{
      module: module,
      uses: uses,
      imports: imports,
      requires: requires,
      aliases: aliases,
      attributes: attributes
    }

    functions =
      aggregate_expressions(:def, exprs, context)
      |> inject_module_info_callback()

    fields =
      Map.from_struct(context)
      |> Map.put(:functions, functions)
      |> Map.put(:macros, macros)

    struct(ModuleDefinition, fields)
  end

  defp fetch_module_body(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, exprs}]]} = ast
    exprs
  end

  defp inject_module_info_callback(functions) do
    name_arity_pairs =
      Enum.map(functions, &"#{&1.name}: #{&1.arity}")
      |> Enum.uniq()

    ir =
      "def __info__(:functions), do: [#{Enum.join(name_arity_pairs, ", ")}]"
      |> Helpers.ir()

    [ir | functions]
  end
end
