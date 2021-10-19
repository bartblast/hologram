alias Hologram.Compiler.{Encoder, Helpers}
alias Hologram.Compiler.IR.ModuleType

defimpl Encoder, for: ModuleType do
  def encode(%{module: module}, _, _) do
    "{ type: 'module', className: '#{Helpers.class_name(module)}' }"
  end
end
