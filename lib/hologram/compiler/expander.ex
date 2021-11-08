defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.{Helpers, Normalizer, Reflection}
  alias Hologram.Compiler.IR.{MacroDefinition, RequireDirective}

  def expand_macro(%MacroDefinition{module: module, name: name}, args) do
    expand_macro(module, name, args)
  end

  def expand_macro(module, name, args) do
    expanded =
      apply(module, :"MACRO-#{name}", [__ENV__] ++ args)
      |> Normalizer.normalize()

    case expanded do
      {:__block__, [], exprs} ->
        exprs

      _ ->
        [expanded]
    end
  end

  def expand_macros(ast, requires) do
    expand_with_fun(ast, &expand_macros_in_expression(&1, requires))
  end

  defp expand_macros_in_expression({name, _, args} = expr, requires) do
    args = if args, do: args, else: []
    macro_def = find_macro_definition(name, args, requires)

    if macro_def do
      expand_macro(macro_def, args)
    else
      expr
    end
  end

  defp expand_macros_in_expression(expr, _), do: expr

  def expand_module_pseudo_variable(
        {:defmodule, ast_1,
         [{:__aliases__, ast_2, module_segs}, [do: {:__block__, ast_3, exprs}]]}
      ) do
    exprs =
      Enum.reduce(exprs, [], fn expr, acc ->
        acc ++ [expand_module_pseudo_variable(expr, module_segs)]
      end)

    {:defmodule, ast_1, [{:__aliases__, ast_2, module_segs}, [do: {:__block__, ast_3, exprs}]]}
  end

  defp expand_module_pseudo_variable({:__MODULE__, line, _}, module_segs) do
    {:__aliases__, line, module_segs}
  end

  defp expand_module_pseudo_variable(ast, module_segs) when is_tuple(ast) do
    Tuple.to_list(ast)
    |> expand_module_pseudo_variable(module_segs)
    |> List.to_tuple()
  end

  defp expand_module_pseudo_variable(ast, module_segs) when is_list(ast) do
    Enum.map(ast, &expand_module_pseudo_variable(&1, module_segs))
  end

  defp expand_module_pseudo_variable(ast, _), do: ast

  defp expand_use_directive({:use, _, [{:__aliases__, _, module_segs}]}) do
    Helpers.module(module_segs)
    |> expand_macro(:__using__, [nil])
  end

  defp expand_use_directive(ast), do: ast

  def expand_use_directives(ast) do
    expand_with_fun(ast, &expand_use_directive/1)
  end

  defp expand_with_fun({:defmodule, line, [aliases, [do: {:__block__, _, exprs}]]}, fun) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case fun.(expr) do
          # expanded expression is returned wrapped in a list
          expr when is_list(expr) ->
            acc ++ expr

          # non-expandable expression
          expr ->
            acc ++ [expr]
        end
      end)

    {:defmodule, line, [aliases, [do: {:__block__, [], expanded}]]}
  end

  defp find_macro_definition(name, args, requires) do
    require_directive =
      Enum.find(requires, fn %RequireDirective{module: module} ->
        Reflection.has_macro?(module, name, Enum.count(args))
      end)

    if require_directive do
      Reflection.macro_definition(require_directive.module, name, args)
    else
      nil
    end
  end
end
