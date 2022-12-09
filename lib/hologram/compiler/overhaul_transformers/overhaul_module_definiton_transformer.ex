defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.{Context, Expander, Helpers, Reflection, Transformer}
  alias Hologram.Compiler.IR.{FunctionHead, ModuleDefinition}

  def transform(ast) do
    exprs = fetch_module_body(ast)
    uses = aggregate_expressions(:use, exprs, %Context{})

    ast = Expander.expand_use_directives(ast)
    exprs = fetch_module_body(ast)
    requires = aggregate_expressions(:require, exprs, %Context{})

    # TODO: enable
    # Expander.expand_macros(ast, requires)
    ast
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
    module_type_fields = determine_module_type_fields(uses)

    context = %Context{
      module: module,
      uses: uses,
      imports: imports,
      requires: requires,
      aliases: aliases,
      attributes: attributes
    }

    defs = aggregate_expressions(:def, exprs, context)
    defps = aggregate_expressions(:defp, exprs, context)

    functions =
      (defs ++ defps)
      |> Enum.reject(&(&1.__struct__ == FunctionHead))
      |> inject_module_info_callback(context)

    fields =
      Map.from_struct(context)
      |> Map.put(:functions, functions)
      |> Map.put(:macros, macros)
      |> Map.merge(module_type_fields)

    struct(ModuleDefinition, fields)
  end

  defp fetch_module_body(ast) do
    {:defmodule, _, [_, [do: {:__block__, _, exprs}]]} = ast
    exprs
  end

  defp inject_module_info_callback(functions, context) do
    name_arity_pairs =
      Enum.map(functions, &"#{&1.name}: #{&1.arity}")
      |> Enum.uniq()

    ir =
      "def __info__(:functions), do: [#{Enum.join(name_arity_pairs, ", ")}]"
      |> Reflection.ir(context)

    [ir | functions]
  end

  defp determine_module_type_fields(uses) do
    fields = %{
      component?: false,
      layout?: false,
      page?: false,
      templatable?: false
    }

    cond do
      Enum.any?(uses, &(&1.module == Hologram.Component)) ->
        Map.merge(fields, %{component?: true, templatable?: true})

      Enum.any?(uses, &(&1.module == Hologram.Layout)) ->
        Map.merge(fields, %{layout?: true, templatable?: true})

      Enum.any?(uses, &(&1.module == Hologram.Page)) ->
        Map.merge(fields, %{page?: true, templatable?: true})

      true ->
        fields
    end
  end
end
