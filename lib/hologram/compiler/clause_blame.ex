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

  defp build_guard({{:., _dot_meta, [:erlang, :andalso]}, _call_meta, [left, right]}) do
    {:and, build_guard(left), build_guard(right)}
  end

  defp build_guard({{:., _dot_meta, [:erlang, :orelse]}, _call_meta, [left, right]}) do
    {:or, build_guard(left), build_guard(right)}
  end

  defp build_guard(ast) do
    source =
      ast
      |> rewrite_guard()
      |> Macro.to_string()

    {:leaf, source, ast}
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
