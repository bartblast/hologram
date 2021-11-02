alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.DotOperator

defimpl JSEncoder, for: DotOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(Kernel.SpecialForms)

    left = JSEncoder.encode(left, context, opts)
    right = JSEncoder.encode(right, context, opts)

    "#{class_name}.$dot(#{left}, #{right})"
  end
end
