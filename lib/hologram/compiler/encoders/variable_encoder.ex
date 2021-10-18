alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.Variable

defimpl Encoder, for: Variable do
  def encode(_, %Context{}, %Opts{placeholder: true}) do
    "{ type: 'placeholder' }"
  end

  def encode(%Variable{name: name}, %Context{}, %Opts{}) do
    "#{name}"
  end
end
