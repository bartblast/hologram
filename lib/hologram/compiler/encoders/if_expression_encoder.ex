alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.{AnonymousFunctionType, IfExpression}

defimpl Encoder, for: IfExpression do
  def encode(
        %{condition: condition, do: do_clause, else: else_clause},
        %Context{} = context,
        %Opts{} = opts
      ) do
    condition = encode_anonymous_function([condition], context, opts)
    do_clause = encode_anonymous_function(do_clause, context, opts)
    else_clause = encode_anonymous_function(else_clause, context, opts)

    "Elixir_Kernel.if(#{condition}, #{do_clause}, #{else_clause})"
  end

  defp encode_anonymous_function(body, context, opts) do
    %AnonymousFunctionType{body: body}
    |> Encoder.encode(context, opts)
  end
end
