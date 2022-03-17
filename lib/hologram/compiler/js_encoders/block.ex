alias Hologram.Compiler.{Config, Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.{Block, MatchOperator}

defimpl JSEncoder, for: Block do
  def encode(%{expressions: exprs}, %Context{} = context, %Opts{} = opts) do
    expr_count = Enum.count(exprs)

    exprs
    |> Enum.with_index()
    |> Enum.map_reduce(context, fn {expr, idx}, context ->
      encode_expr(expr, idx, expr_count, context, opts)
    end)
    |> elem(0)
    |> Enum.join("\n")
  end

  defp build_output(%MatchOperator{} = expr, idx, expr_count, context, opts) do
    output = JSEncoder.encode(expr, context, opts)

    if idx == expr_count - 1 do
      output <> "\nreturn #{Config.matchAccessJS()};"
    else
      output
    end
  end

  defp build_output(expr, idx, expr_count, context, opts) do
    return_statement = if idx == expr_count - 1, do: "return ", else: ""
    "#{return_statement}#{JSEncoder.encode(expr, context, opts)};"
  end

  defp encode_expr(expr, idx, expr_count, context, opts) do
    output = build_output(expr, idx, expr_count, context, opts)
    block_bindings = context.block_bindings ++ get_expr_bindings(expr)
    context = %{context | block_bindings: block_bindings}

    {output, context}
  end

  defp get_expr_bindings(%MatchOperator{bindings: bindings}) do
    Enum.map(bindings, fn %{name: name} -> name end)
  end

  defp get_expr_bindings(_), do: []
end
