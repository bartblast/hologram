defmodule Hologram.Compiler.Transformer do
  import Hologram.Compiler.Macros, only: [transform: 2]

  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.PatternDeconstructor
  alias Hologram.Compiler.Reflection

  @doc """
  Transforms Elixir AST to Hologram IR.

  ## Examples
      iex> ast = quote do 1 + 2 end
      {:+, [context: Elixir, imports: [{1, Kernel}, {2, Kernel}]], [1, 2]}
      iex> Transformer.transform(ast)
      %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
  """
  def transform(ast)

  # --- OPERATORS ---

  transform({{:., _, [{:__aliases__, [alias: false], [:Access]}, :get]}, _, [data, key]}) do
    %IR.AccessOperator{
      data: transform(data),
      key: transform(key)
    }
  end

  transform({:+, _, [left, right]}) do
    %IR.AdditionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform([{:|, _, [head, tail]}]) do
    %IR.ConsOperator{
      head: transform(head),
      tail: transform(tail)
    }
  end

  transform({:/, _, [left, right]}) do
    %IR.DivisionOperator{
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

  transform _({{:., _, [{marker, _, _} = left, right]}, [no_parens: true, line: _], []})
            when marker not in [:__aliases__, :__MODULE__] do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:==, _, [left, right]}) do
    %IR.EqualToOperator{
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

  transform({:=, _, [left, right]}) do
    left = transform(left)

    bindings =
      left
      |> PatternDeconstructor.deconstruct()
      |> Enum.map(fn path ->
        [head | tail] = Enum.reverse(path)
        access_path = [%IR.MatchAccess{} | Enum.reverse(tail)]
        %IR.Binding{name: head.name, access_path: access_path}
      end)

    %IR.MatchOperator{
      bindings: bindings,
      left: left,
      right: transform(right)
    }
  end

  transform({:in, _, [left, right]}) do
    %IR.MembershipOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  transform({:@, _, [{name, _, nil}]}) do
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

  transform _(ast) when is_atom(ast) and ast not in [nil, false, true] do
    %IR.AtomType{value: ast}
  end

  transform({:<<>>, _, parts}) do
    %IR.BinaryType{parts: transform_list(parts)}
  end

  transform _(ast) when is_boolean(ast) do
    %IR.BooleanType{value: ast}
  end

  transform _(ast) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  transform _(ast) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  transform _(ast) when is_list(ast) do
    data = Enum.map(ast, &transform/1)
    %IR.ListType{data: data}
  end

  transform({:%{}, _, data}) do
    {module, new_data} = Keyword.pop(data, :__struct__)

    data_ir =
      Enum.map(new_data, fn {key, value} ->
        {transform(key), transform(value)}
      end)

    if module do
      segments = Helpers.alias_segments(module)
      module_ir = %IR.ModuleType{module: module, segments: segments}
      %IR.StructType{module: module_ir, data: data_ir}
    else
      %IR.MapType{data: data_ir}
    end
  end

  transform(nil) do
    %IR.NilType{}
  end

  transform _(ast) when is_binary(ast) do
    %IR.StringType{value: ast}
  end

  transform({:%, _, [alias_ast, map_ast]}) do
    module = transform(alias_ast)
    data = transform(map_ast).data

    %IR.StructType{module: module, data: data}
  end

  transform({:{}, _, data}) do
    build_tuple_type_ir(data)
  end

  transform({_, _} = data) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir()
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

  transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
  end

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
    %IR.FunctionCall{
      module: module,
      function: function,
      args: transform_list(args),
      erlang: true
    }
  end

  transform({:if, _, [condition, [do: do_block, else: else_block]]}) do
    %IR.IfExpression{
      condition: transform(condition),
      do: transform(do_block),
      else: transform(else_block)
    }
  end

  # preserve order:

  transform _({function, _, args}) when is_atom(function) and is_list(args) do
    build_call_ir(nil, function, args)
  end

  transform _({name, _, _}) when is_atom(name) do
    %IR.Symbol{name: name}
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

  defp build_tuple_type_ir(data) do
    data = Enum.map(data, &transform/1)
    %IR.TupleType{data: data}
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

  defp transform_list(list) do
    list
    |> List.wrap()
    |> Enum.map(&transform/1)
  end
end
