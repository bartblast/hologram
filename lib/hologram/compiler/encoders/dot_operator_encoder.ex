alias Hologram.Compiler.{Context, Encoder, Helpers, Opts}
alias Hologram.Compiler.IR.DotOperator

defimpl Encoder, for: DotOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(Kernel.SpecialForms)

    left = Encoder.encode(left, context, opts)
    right = Encoder.encode(right, context, opts)

    "#{class_name}.$dot(#{left}, #{right})"
  end
end
