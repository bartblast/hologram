alias Hologram.Compiler.{Helpers, JSEncoder}
alias Hologram.Compiler.IR.ModuleType

defimpl JSEncoder, for: ModuleType do
  def encode(%{module: module}, _, _) do
    "{ type: 'module', className: '#{Helpers.class_name(module)}' }"
  end
end
