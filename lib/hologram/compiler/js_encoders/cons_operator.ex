alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.ConsOperator

defimpl JSEncoder, for: ConsOperator do
  def encode(%{head: head, tail: tail}, %Context{} = context, %Opts{} = opts) do
    encoded_head = JSEncoder.encode(head, context, opts)
    encoded_tail = JSEncoder.encode(tail, context, opts)

    "Hologram.Interpreter.$cons_operator(#{encoded_head}, #{encoded_tail})"
  end
end
