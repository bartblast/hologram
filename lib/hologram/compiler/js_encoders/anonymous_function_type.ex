alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl JSEncoder, for: AnonymousFunctionType do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{bindings: bindings, body: body}, %Context{} = context, %Opts{} = opts) do
    vars = encode_vars(bindings, context, " ")
    body = encode_expressions(body, context, opts, " ")

    "(function() {"
    |> Formatter.maybe_append_new_expression(vars)
    |> Formatter.maybe_append_new_expression(body)
    |> Formatter.maybe_append_new_expression("})")
  end
end
