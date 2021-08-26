defmodule Hologram.Compiler.Encoder.Commons do
  alias Hologram.Compiler.Generator

  defp generate_expression(expr, idx, expr_count, context, opts) do
    return = if idx == expr_count - 1, do: "return ", else: ""
    "#{return}#{Generator.generate(expr, context, opts)};"
  end

  def generate_expressions(body, context, opts, separator) do
    expr_count = Enum.count(body)

    Enum.with_index(body)
    |> Enum.map(fn {expr, idx} -> generate_expression(expr, idx, expr_count, context, opts) end)
    |> Enum.join(separator)
  end
end
