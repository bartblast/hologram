alias Hologram.Compiler.{Context, JSEncoder, Opts}
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

  defp encode_expr(expr, idx, expr_count, context, opts) do
    return_statement = if idx == expr_count - 1, do: "return ", else: ""
    output = "#{return_statement}#{JSEncoder.encode(expr, context, opts)};"

    block_bindings = context.block_bindings ++ get_expr_bindings(expr)
    context = %{context | block_bindings: block_bindings}

    {output, context}
  end

  defp get_expr_bindings(expr) do
    case expr do
      %MatchOperator{bindings: bindings} ->
        Enum.map(bindings, fn {name, _} -> name end)
      _ ->
        []
    end
  end
end
