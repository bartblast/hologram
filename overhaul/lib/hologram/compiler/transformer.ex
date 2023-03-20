defmodule Hologram.Compiler.Transformer do
  import Hologram.Compiler.Macros, only: [transform: 2]

  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.PatternDeconstructor
  alias Hologram.Compiler.Reflection

  # --- OPERATORS ---

  transform _({{:., _, [{marker, _, _} = left, right]}, [no_parens: true, line: _], []})
            when marker not in [:__aliases__, :__MODULE__] do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform _({{:., _, [{marker, _, _} = left, right]}, [no_parens: true, line: _], []})
            when marker not in [:__aliases__, :__MODULE__] do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:<, _, [left, right]}) do
    %IR.LessThanOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:++, _, [left, right]}) do
    %IR.ListConcatenationOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:--, _, [left, right]}) do
    %IR.ListSubtractionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:in, _, [left, right]}) do
    %IR.MembershipOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform _({:@, _, [{name, _, term}]}) when not is_list(term) do
    %IR.ModuleAttributeOperator{name: name}
  end

  transform({:*, _, [left, right]}) do
    %IR.MultiplicationOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:!=, _, [left, right]}) do
    %IR.NotEqualToOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  # based on: https://ianrumford.github.io/elixir/pipe/clojure/thread-first/macro/2016/07/24/writing-your-own-elixir-pipe-operator.html
  transform({:|>, _, _} = ast) do
    [{first_ast, _index} | rest_tuples] = Macro.unpipe(ast)

    rest_tuples
    |> Enum.reduce(first_ast, fn {rest_ast, rest_index}, this_ast ->
      Macro.pipe(this_ast, rest_ast, rest_index)
    end)
    |> transform()
  end

  transform({:&&, _, [left, right]}) do
    %IR.RelaxedBooleanAndOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:__block__, _, [{:!, _, [value]}]}) do
    build_relaxed_boolean_not_operator_ir(value)
  end

  transform({:!, _, [value]}) do
    build_relaxed_boolean_not_operator_ir(value)
  end

  transform({:||, _, [left, right]}) do
    %IR.RelaxedBooleanOrOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:and, _, [left, right]}) do
    %IR.StrictBooleanAndOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:-, _, [left, right]}) do
    %IR.SubtractionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:"::", _, [left, {right, _, _}]}) do
    %IR.TypeOperator{
      left: transform(left),
      right: right
    }
  end

  transform({:-, _, [value]}) do
    %IR.UnaryNegativeOperator{
      value: transform(value)
    }
  end

  transform({:+, _, [value]}) do
    %IR.UnaryPositiveOperator{
      value: transform(value)
    }
  end

  # --- DATA TYPES ---

  transform({:fn, _, [{:->, _, [params, body]}]}) do
    params = transform_list(params)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = transform(body)

    %IR.AnonymousFunctionType{arity: arity, params: params, bindings: bindings, body: body}
  end

  # --- PSEUDO-VARIABLES ---

  transform({:__ENV__, _, _}) do
    %IR.EnvPseudoVariable{}
  end

  transform({:__MODULE__, _, _}) do
    %IR.ModulePseudoVariable{}
  end

  # --- DEFINITIONS ---

  transform _({marker, _, [{name, _, params}, [do: body]]}) when marker in [:def, :defp] do
    params = transform_list(params)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = transform(body)
    visibility = if marker == :def, do: :public, else: :private

    %IR.FunctionDefinition{
      name: name,
      arity: arity,
      params: params,
      bindings: bindings,
      body: body,
      visibility: visibility
    }
  end

  transform({:@, _, [{name, _, [ast]}]}) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: transform(ast)
    }
  end

  transform({:defmodule, _, [module, [do: body]]}) do
    %IR.ModuleDefinition{
      module: transform(module),
      body: transform(body)
    }
  end

  # --- DIRECTIVES ---

  transform({:alias, _, [{{_, _, [{_, _, alias_segs}, _]}, _, aliases}, _]}) do
    build_alias_directive_irs(alias_segs, aliases)
  end

  transform({:alias, _, [{{_, _, [{_, _, alias_segs}, _]}, _, aliases}]}) do
    build_alias_directive_irs(alias_segs, aliases)
  end

  transform({:alias, _, [{_, _, alias_segs}]}) do
    %IR.AliasDirective{alias_segs: alias_segs, as: List.last(alias_segs)}
  end

  transform({:alias, _, [{_, _, alias_segs}, opts]}) do
    as =
      if Keyword.has_key?(opts, :as) do
        {:__aliases__, _, [alias_seg | _]} = opts[:as]
        alias_seg
      else
        List.last(alias_segs)
      end

    %IR.AliasDirective{alias_segs: alias_segs, as: as}
  end

  transform({:import, _, [{:__aliases__, _, alias_segs}, opts]}) do
    only = if opts[:only], do: opts[:only], else: []
    except = if opts[:except], do: opts[:except], else: []

    build_import_directive_ir(alias_segs, only, except)
  end

  transform({:import, _, [{:__aliases__, _, alias_segs}]}) do
    build_import_directive_ir(alias_segs, [], [])
  end

  transform({:defmacro, _, _}) do
    %IR.IgnoredExpression{type: :public_macro_definition}
  end

  transform({:require, _, _}) do
    %IR.IgnoredExpression{type: :require_directive}
  end

  transform({:use, _, [{_, _, alias_segs}]}) do
    %IR.UseDirective{alias_segs: alias_segs, opts: []}
  end

  transform({:use, _, [{_, _, alias_segs}, opts]}) do
    %IR.UseDirective{
      alias_segs: alias_segs,
      opts: transform(opts)
    }
  end

  # --- CONTROL FLOW ---

  transform({{:., _, [{name, _, nil}]}, _, args}) do
    %IR.AnonymousFunctionCall{
      name: name,
      args: Enum.map(args, &transform/1)
    }
  end

  transform({:__block__, _, ast}) do
    ir = Enum.map(ast, &transform/1)
    %IR.Block{expressions: ir}
  end

  transform _({{:., _, [module, function]}, _, args}) when not is_atom(module) do
    build_call_ir(module, function, args)
  end

  transform({:case, _, [condition, [do: clauses]]}) do
    %IR.CaseExpression{
      condition: transform(condition),
      clauses: Enum.map(clauses, &build_case_clause_ir/1)
    }
  end

  transform({:for, _, parts}) do
    generators = find_for_expression_generators(parts)
    mapper = find_for_expression_mapper(parts)

    generators
    |> rewrite_for_expression_code(mapper)
    |> Reflection.ast()
    |> transform()
  end

  transform _({{:., _, [module, function]}, _, args}) when is_atom(module) do
    args = transform_list(args)

    if Reflection.is_alias?(module) do
      segments = Helpers.alias_segments(module)

      %IR.Call{
        module: %IR.Alias{segments: segments},
        function: function,
        args: args
      }
    else
      %IR.FunctionCall{
        module: module,
        function: function,
        args: args,
        erlang: true
      }
    end
  end

  transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
    %IR.IfExpression{
      condition: transform(condition),
      do: transform(do_block),
      else: transform(else_block)
    }
  end

  # preserve order:

  transform _({function, [context: _, imports: [{_arity, module}]], args})
            when is_atom(function) and is_list(args) do
    segments = Helpers.alias_segments(module)
    module_ir = %IR.ModuleType{module: module, segments: segments}
    build_call_ir(module_ir, function, args)
  end

  transform _({function, [context: _, imports: [{_arity, called_module}]], calling_module})
            when is_atom(function) and not is_list(calling_module) do
    segments = Helpers.alias_segments(called_module)
    module_ir = %IR.ModuleType{module: called_module, segments: segments}
    build_call_ir(module_ir, function, [])
  end

  transform _({function, _, args}) when is_atom(function) and is_list(args) do
    build_call_ir(nil, function, args)
  end

  # --- HELPERS ---

  defp build_call_ir(module, function, args) do
    new_module =
      case module do
        nil ->
          nil

        %IR.ModuleType{} ->
          module

        module ->
          transform(module)
      end

    %IR.Call{
      module: new_module,
      function: function,
      args: transform_list(args)
    }
  end

  defp build_alias_directive_irs(alias_segs, aliases) do
    Enum.map(aliases, fn {:__aliases__, _, [as]} ->
      %IR.AliasDirective{alias_segs: alias_segs ++ [as], as: as}
    end)
  end

  defp build_case_clause_ir({:->, _, [[pattern], body]}) do
    pattern = transform(pattern)
    body = transform(body)

    bindings =
      Helpers.aggregate_bindings_from_expression(pattern)
      |> Enum.map(&prepend_case_condition_access/1)

    %{
      pattern: pattern,
      bindings: bindings,
      body: body
    }
  end

  defp build_import_directive_ir(alias_segs, only, except) do
    %IR.ImportDirective{alias_segs: alias_segs, only: only, except: except}
  end

  defp build_relaxed_boolean_not_operator_ir(value) do
    %IR.RelaxedBooleanNotOperator{
      value: transform(value)
    }
  end

  defp find_for_expression_generators(parts) do
    Enum.filter(parts, fn part ->
      match?({:<-, _, _}, part)
    end)
  end

  defp find_for_expression_mapper(parts) do
    List.last(parts)
  end

  defp prepend_case_condition_access(binding) do
    %{binding | access_path: [%IR.CaseConditionAccess{} | binding.access_path]}
  end

  defp rewrite_for_expression_code([generator | rest_of_generators], mapper) do
    {:<-, _, [pattern, elems]} = generator

    """
    Enum.reduce(#{Macro.to_string(elems)}, [], fn holo_el__, holo_acc__ ->
    #{Macro.to_string(pattern)} = holo_el__
    holo_acc__ ++ #{rewrite_for_expression_code(rest_of_generators, mapper)}
    end)
    """
  end

  defp rewrite_for_expression_code([], mapper) do
    [do: {:__block__, _, [mapper_expr]}] = mapper
    "[#{Macro.to_string(mapper_expr)}]"
  end
end
