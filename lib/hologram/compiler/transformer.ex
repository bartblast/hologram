defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.PatternDeconstructor

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

  def transform({{:., _, [{:__aliases__, [alias: false], [:Access]}, :get]}, _, [data, key]}) do
    %IR.AccessOperator{
      data: transform(data),
      key: transform(key)
    }
  end

  def transform({:+, _, [left, right]}) do
    %IR.AdditionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform([{:|, _, [head, tail]}]) do
    %IR.ConsOperator{
      head: transform(head),
      tail: transform(tail)
    }
  end

  def transform({:/, _, [left, right]}) do
    %IR.DivisionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({{:., _, [{marker, _, _} = left, right]}, [no_parens: true, line: _], []})
      when marker not in [:__aliases__, :__MODULE__] do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:==, _, [left, right]}) do
    %IR.EqualToOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:<, _, [left, right]}) do
    %IR.LessThanOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:++, _, [left, right]}) do
    %IR.ListConcatenationOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:--, _, [left, right]}) do
    %IR.ListSubtractionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:=, _, [left, right]}) do
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

  def transform({:in, _, [left, right]}) do
    %IR.MembershipOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:@, _, [{name, _, nil}]}) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:*, _, [left, right]}) do
    %IR.MultiplicationOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:!=, _, [left, right]}) do
    %IR.NotEqualToOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  # based on: https://ianrumford.github.io/elixir/pipe/clojure/thread-first/macro/2016/07/24/writing-your-own-elixir-pipe-operator.html
  def transform({:|>, _, _} = ast) do
    [{first_ast, _index} | rest_tuples] = Macro.unpipe(ast)

    rest_tuples
    |> Enum.reduce(first_ast, fn {rest_ast, rest_index}, this_ast ->
      Macro.pipe(this_ast, rest_ast, rest_index)
    end)
    |> transform()
  end

  def transform({:&&, _, [left, right]}) do
    %IR.RelaxedBooleanAndOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:__block__, _, [{:!, _, [value]}]}) do
    build_relaxed_boolean_not_operator_ir(value)
  end

  def transform({:!, _, [value]}) do
    build_relaxed_boolean_not_operator_ir(value)
  end

  def transform({:||, _, [left, right]}) do
    %IR.RelaxedBooleanOrOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:and, _, [left, right]}) do
    %IR.StrictBooleanAndOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:+, _, [value]}) do
    %IR.UnaryPositiveOperator{
      value: transform(value)
    }
  end

  # --- DATA TYPES ---

  def transform({:fn, _, [{:->, _, [params, body]}]}) do
    params = transform_params(params)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = transform(body)

    %IR.AnonymousFunctionType{arity: arity, params: params, bindings: bindings, body: body}
  end

  # TODO: implement anonymous functions with multiple clauses
  def transform({:fn, _, _} = ast) do
    %IR.NotSupportedExpression{
      type: :multi_clause_anonymous_function_type,
      ast: ast
    }
  end

  def transform(ast) when is_atom(ast) and ast not in [nil, false, true] do
    %IR.AtomType{value: ast}
  end

  def transform({:<<>>, _, parts}) do
    %IR.BinaryType{parts: transform_params(parts)}
  end

  def transform(ast) when is_boolean(ast) do
    %IR.BooleanType{value: ast}
  end

  def transform(ast) when is_float(ast) do
    %IR.FloatType{value: ast}
  end

  def transform(ast) when is_integer(ast) do
    %IR.IntegerType{value: ast}
  end

  def transform(ast) when is_list(ast) do
    data = Enum.map(ast, &transform/1)
    %IR.ListType{data: data}
  end

  def transform({:%{}, _, data}) do
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

  def transform(nil) do
    %IR.NilType{}
  end

  def transform(ast) when is_binary(ast) do
    %IR.StringType{value: ast}
  end

  def transform({:%, _, [alias_ast, map_ast]}) do
    module = transform(alias_ast)
    data = transform(map_ast).data

    %IR.StructType{module: module, data: data}
  end

  def transform({:{}, _, data}) do
    build_tuple_type_ir(data)
  end

  def transform({_, _} = data) do
    data
    |> Tuple.to_list()
    |> build_tuple_type_ir()
  end

  # --- PSEUDO-VARIABLES ---

  def transform({:__ENV__, _, _}) do
    %IR.EnvPseudoVariable{}
  end

  def transform({:__MODULE__, _, _}) do
    %IR.ModulePseudoVariable{}
  end

  # --- DEFINITIONS ---

  def transform({marker, _, [{name, _, params}, [do: body]]}) when marker in [:def, :defp] do
    params = transform_params(params)
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

  def transform({:@, _, [{name, _, [ast]}]}) do
    %IR.ModuleAttributeDefinition{
      name: name,
      expression: transform(ast)
    }
  end

  # --- CONTROL FLOW ---

  def transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
  end

  def transform({{:., _, [{name, _, nil}]}, _, args}) do
    %IR.AnonymousFunctionCall{
      name: name,
      args: Enum.map(args, &transform/1)
    }
  end

  def transform({:__block__, _, ast}) do
    ir = Enum.map(ast, &transform/1)
    %IR.Block{expressions: ir}
  end

  def transform({{:., _, [module, function]}, _, args}) when not is_atom(module) do
    build_call_ir(module, function, args)
  end

  def transform({function, _, args}) when is_atom(function) and is_list(args) do
    build_call_ir(nil, function, args)
  end

  def transform({{:., _, [module, function]}, _, args}) when is_atom(module) do
    %IR.FunctionCall{
      module: module,
      function: function,
      args: transform_params(args),
      erlang: true
    }
  end

  def transform({name, _, _}) when is_atom(name) do
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
      args: transform_params(args)
    }
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

  def transform_params(params) do
    params
    |> List.wrap()
    |> Enum.map(&transform/1)
  end
end
