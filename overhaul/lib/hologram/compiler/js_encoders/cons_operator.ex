alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.ConsOperator

defimpl JSEncoder, for: ConsOperator do
  def encode(ir, %Context{} = context, %Opts{placeholder: true} = opts) do
    {head, tail} = encode_parts(ir, context, opts)
    "{ type: 'cons_operator_pattern', head: #{head}, tail: #{tail} }"
  end

  def encode(ir, %Context{} = context, %Opts{} = opts) do
    {head, tail} = encode_parts(ir, context, opts)
    "Hologram.Interpreter.$cons_operator(#{head}, #{tail})"
  end

  defp encode_parts(%{head: head, tail: tail}, context, opts) do
    {
      JSEncoder.encode(head, context, opts),
      JSEncoder.encode(tail, context, opts)
    }
  end
end
