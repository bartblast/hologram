alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.MembershipOperator

defimpl JSEncoder, for: MembershipOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "Hologram.Interpreter.$membership_operator(#{left}, #{right})"
  end
end
