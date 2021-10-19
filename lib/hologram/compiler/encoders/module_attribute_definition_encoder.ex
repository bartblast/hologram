alias Hologram.Compiler.{Context, Encoder, Opts}
alias Hologram.Compiler.IR.ModuleAttributeDefinition

defimpl Encoder, for: ModuleAttributeDefinition do
  def encode(%{name: name, value: value}, %Context{} = context, %Opts{} = opts) do
    value = Encoder.encode(value, context, opts)
    "static $#{name} = #{value};"
  end
end
