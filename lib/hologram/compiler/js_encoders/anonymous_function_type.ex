alias Hologram.Compiler.{Context, Formatter, JSEncoder, Opts}
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl JSEncoder, for: AnonymousFunctionType do
  use Hologram.Commons.Encoder

  def encode(%{bindings: bindings, body: body}, %Context{} = context, %Opts{} = opts) do
    vars = encode_vars(bindings, context, opts)

    vars_bindings = Enum.map(bindings, & &1.name)
    context = %{context | block_bindings: context.block_bindings ++ vars_bindings}
    body = JSEncoder.encode(body, context, opts)

    "function() {"
    |> Formatter.maybe_append_new_line(vars)
    |> Formatter.maybe_append_new_line(body)
    |> Formatter.maybe_append_new_line("}")
  end
end
