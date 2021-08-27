defmodule Hologram.Compiler.Encoder.Commons do
  alias Hologram.Compiler.{Generator, MapKeyGenerator}
  alias Hologram.Compiler.IR.{AccessOperator, Variable}

  defp encode_expression(expr, idx, expr_count, context, opts) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "#{return}#{Generator.generate(expr, context, opts)};"
  end

  def encode_expressions(body, context, opts, separator) do
    expr_count = Enum.count(body)

    Enum.with_index(body)
    |> Enum.map(fn {expr, idx} -> encode_expression(expr, idx, expr_count, context, opts) end)
    |> Enum.join(separator)
  end

  defp encode_var({name, {idx, path}}, context) do
    acc = "let #{name} = arguments[#{idx}]"

    value =
      Enum.reduce(path, acc, fn type, acc ->
        acc <>
          case type do
            %AccessOperator{key: key} ->
              ".data['#{MapKeyGenerator.generate(key, context)}']"

            %Variable{} ->
              ""
          end
      end)

    "#{value};"
  end

  def encode_vars(bindings, context, separator) do
    Enum.map(bindings, &encode_var(&1, context))
    |> Enum.join(separator)
  end
end
