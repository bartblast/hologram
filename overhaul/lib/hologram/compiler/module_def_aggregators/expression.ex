alias Hologram.Compiler.ModuleDefAggregator
alias Hologram.Template.VDOM.Expression

defimpl ModuleDefAggregator, for: Expression do
  def aggregate(%{ir: ir}) do
    ModuleDefAggregator.aggregate(ir)
  end
end
