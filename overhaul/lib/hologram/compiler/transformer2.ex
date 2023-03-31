defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.Helpers

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

  def transform({:/, _, [left, right]}) do
    %IR.DivisionOperator{
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
    %IR.MatchOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:in, _, [left, right]}) do
    %IR.MembershipOperator{
      left: transform(left),
      right: transform(right)
    }
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

  def transform({:^, _, [{name, _, _}]}) do
    %IR.PinOperator{name: name}
  end

  # Pipe operator, based on: https://ianrumford.github.io/elixir/pipe/clojure/thread-first/macro/2016/07/24/writing-your-own-elixir-pipe-operator.html
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

  def transform({:-, _, [left, right]}) do
    %IR.SubtractionOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:"::", _, [left, {right, _, _}]}) do
    %IR.TypeOperator{
      left: transform(left),
      right: right
    }
  end

  # --- DATA TYPES ---

  def transform({:<<>>, _, parts}) do
    %IR.BinaryType{parts: transform_list(parts)}
  end

  def transform(ast) when is_binary(ast) do
    %IR.StringType{value: ast}
  end

  # --- HELPERS ---

  defp build_relaxed_boolean_not_operator_ir(value) do
    %IR.RelaxedBooleanNotOperator{
      value: transform(value)
    }
  end
end
