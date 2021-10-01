alias Hologram.Compiler.{Context, Encoder, Generator, Opts}
alias Hologram.Compiler.IR.ModuleAttributeDefinition

defimpl Encoder, for: ModuleAttributeDefinition do
  def encode(%ModuleAttributeDefinition{} = ir, %Context{} = context, %Opts{} = opts) do
    value = Generator.generate(ir.value, context, opts)
    "static $#{ir.name} = #{value};"
  end
end
