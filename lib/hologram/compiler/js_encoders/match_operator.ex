alias Hologram.Compiler.{Context, JSEncoder, Opts}

alias Hologram.Compiler.IR.{
  DotOperator,
  FunctionCall,
  IntegerType,
  MapAccess,
  MatchOperator,
  TupleAccess
}

defimpl JSEncoder, for: MatchOperator do
  def encode(%{bindings: bindings, right: right}, %Context{} = context, %Opts{} = opts) do
    Enum.map(bindings, fn binding ->
      encode_binding(binding, right, context, opts)
    end)
    |> Enum.join(";\n")
  end

  defp encode_binding({name, path}, right, context, opts) do
  #   let_statement = if name in context.block_bindings, do: "", else: "let "
  #   let_statement <> "#{name} = " <> JSEncoder.encode(ir, context, opts)
  end
end
