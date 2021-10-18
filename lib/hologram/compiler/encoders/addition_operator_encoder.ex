alias Hologram.Compiler.{Context, Encoder, Helpers, Opts}
alias Hologram.Compiler.IR.AdditionOperator

defimpl Encoder, for: AdditionOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = Encoder.encode(left, context, opts)
    right = Encoder.encode(right, context, opts)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$add(#{left}, #{right})"
  end
end
