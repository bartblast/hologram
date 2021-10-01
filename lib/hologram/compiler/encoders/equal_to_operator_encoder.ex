alias Hologram.Compiler.{Context, Encoder, Generator, Helpers, Opts}
alias Hologram.Compiler.IR.EqualToOperator

defimpl Encoder, for: EqualToOperator do
  def encode(%{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    left = Generator.generate(left, context, opts)
    right = Generator.generate(right, context, opts)
    class_name = Helpers.class_name(Kernel)

    "#{class_name}.$equal_to(#{left}, #{right})"
  end
end
