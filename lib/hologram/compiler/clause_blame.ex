defmodule Hologram.Compiler.ClauseBlame do
  @moduledoc false

  # The server renders the "Attempted function clauses" section of a
  # FunctionClauseError message from clause ASTs it reads out of BEAM debug
  # info, marking the parameters and guards that didn't match. The client can
  # read neither BEAM files nor render ASTs (Macro.to_string pulls in the code
  # formatter), so the compiler renders the source texts here, at build time,
  # and the client marks them against the actual arguments at raise time.
  #
  # Guards are split at their top-level and/or operators, because the server
  # marks each operand separately.

  @typedoc """
  A guard split at its top-level and/or operators: either one of those
  operators with its two operands, or a leaf carrying the rendered source of a
  guard expression together with the AST it was rendered from.
  """
  @type guard :: {:and | :or, guard, guard} | {:leaf, String.t(), Macro.t()}

  @doc """
  Splits the given clause guards at their top-level and/or operators, rendering
  each leaf into the source text the server shows for it.

  ## Examples

      iex> build_guards([{{:., [], [:erlang, :is_atom]}, [], [{:module, [], nil}]}])
      [{:leaf, "is_atom(module)", {{:., [], [:erlang, :is_atom]}, [], [{:module, [], nil}]}}]
  """
  @spec build_guards(list(Macro.t())) :: list(guard)
  def build_guards(guards) do
    Enum.map(guards, &build_guard/1)
  end

  @doc """
  Renders the given clause params into the source texts the server shows for
  them.

  ## Examples

      iex> build_params([{:elem, [], nil}, {:n, [], nil}])
      ["elem", "n"]
  """
  @spec build_params(list(Macro.t())) :: list(String.t())
  def build_params(params) do
    Enum.map(params, fn param ->
      param
      |> rewrite_param()
      |> Macro.to_string()
    end)
  end

  defp build_guard(ast) do
    ast
    |> build_node()
    |> collapse_struct_macros()
    |> to_guard()
  end

  defp build_node({{:., _dot_meta, [:erlang, :andalso]}, _call_meta, [left, right]} = ast) do
    {:op, :and, ast, build_node(left), build_node(right)}
  end

  defp build_node({{:., _dot_meta, [:erlang, :orelse]}, _call_meta, [left, right]} = ast) do
    {:op, :or, ast, build_node(left), build_node(right)}
  end

  defp build_node(ast) do
    {:node, ast, rewrite_guard(ast)}
  end

  defp collapse_struct_macros({:op, op, ast, left, right} = node) do
    case struct_macro_args(node) do
      nil ->
        {:op, op, ast, collapse_struct_macros(left), collapse_struct_macros(right)}

      args ->
        {:node, ast, {:is_struct, [], args}}
    end
  end

  defp collapse_struct_macros(node), do: node

  defp map_key_node?({:is_map_key, _meta, [_map, _key]}), do: true
  defp map_key_node?(_node), do: false

  defp map_node?({:is_map, _meta, [_term]}), do: true
  defp map_node?(_node), do: false

  # An is_struct/1,2 guard is spelled out as a conjunction of map, key and
  # struct-field checks, which the server folds back into the macro call when
  # it renders the clause. The conjunction stays as the node's AST, so the
  # client evaluates it as one unit, the way the server marks it as one.
  defp struct_macro_args(
         {:op, :and, _ast,
          {:op, :and, _left_ast, {:node, _map_ast, map_node = {_map_fun, _map_meta, [term]}},
           {:node, _key_ast, key_node = {_key_fun, _key_meta, [term, _key]}}},
          {:node, _validation_ast,
           validation_node =
             {_validation_fun, _validation_meta, [{_get_fun, _get_meta, [_key_name, term]}]}}}
       ) do
    if map_node?(map_node) and map_key_node?(key_node) and
         struct_validation_node?(validation_node) do
      [term]
    end
  end

  defp struct_macro_args(
         {:op, :and, _ast,
          {:op, :and, _left_ast,
           {:op, :and, _innermost_ast,
            {:node, _map_ast, map_node = {_map_fun, _map_meta, [term]}},
            {:op, :or, _or_ast, {:node, _atom_ast, {:is_atom, _atom_meta, [_module_ast]}},
             {:node, _fail_ast, :fail}}},
           {:node, _key_ast, key_node = {_key_fun, _key_meta, [term, _key]}}},
          {:node, _validation_ast,
           validation_node =
             {_validation_fun, _validation_meta,
              [{_get_fun, _get_meta, [_key_name, term]}, module]}}}
       ) do
    if map_node?(map_node) and map_key_node?(key_node) and
         struct_validation_node?(validation_node) do
      [term, module]
    end
  end

  defp struct_macro_args(_node), do: nil

  defp struct_validation_node?(
         {:is_atom, _meta, [{{:., [], [:erlang, :map_get]}, _get_meta, [:__struct__, _term]}]}
       ),
       do: true

  defp struct_validation_node?(
         {:==, _meta, [{{:., [], [:erlang, :map_get]}, _get_meta, [:__struct__, _term]}, _module]}
       ),
       do: true

  defp struct_validation_node?(_node), do: false

  defp to_guard({:op, op, _ast, left, right}) do
    {op, to_guard(left), to_guard(right)}
  end

  defp to_guard({:node, ast, rewritten_ast}) do
    {:leaf, Macro.to_string(rewritten_ast), ast}
  end

  # Debug info spells guards out as :erlang remote calls, which the server maps
  # back to the Kernel names they were written with.
  defp rewrite_guard(ast) do
    Macro.prewalk(ast, fn
      {{:., _dot_meta, [module, function]}, call_meta, args} ->
        case :elixir_rewrite.erl_to_ex(module, function, args) do
          {Kernel, ex_function, ex_args, _arity} ->
            {ex_function, call_meta, ex_args}

          {ex_module, ex_function, ex_args, _arity} ->
            {{:., [], [ex_module, ex_function]}, call_meta, ex_args}
        end

      other ->
        other
    end)
  end

  # Debug info spells a range pattern out as a struct, which the server maps
  # back to the step operator.
  defp rewrite_param(ast) do
    Macro.prewalk(ast, fn
      {:%{}, meta, [__struct__: Range, first: first, last: last, step: step]} ->
        {:..//, meta, [first, last, step]}

      other ->
        other
    end)
  end
end
