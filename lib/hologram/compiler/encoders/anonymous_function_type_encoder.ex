alias Hologram.Compiler.{Context, Encoder, Formatter, Opts}
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl Encoder, for: AnonymousFunctionType  do
  def encode(%{bindings: bindings, body: body}, %Context{} = context, %Opts{} = opts) do
    vars = Hologram.Compiler.FunctionDefinitionGenerator.generate_vars(bindings, context, " ")
    body = Hologram.Compiler.FunctionDefinitionGenerator.generate_exprs(body, context, opts, " ")

    "(function() {"
    |> Formatter.maybe_append_new_expression(vars)
    |> Formatter.maybe_append_new_expression(body)
    |> Formatter.maybe_append_new_expression("})")
  end
end
