alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.ModuleAttributeDefinition

defimpl JSEncoder, for: ModuleAttributeDefinition do
  def encode(%{name: name, value: value}, %Context{} = context, %Opts{} = opts) do
    value = JSEncoder.encode(value, context, opts)
    "static $#{name} = #{value};"
  end
end
