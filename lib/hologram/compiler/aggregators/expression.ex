alias Hologram.Compiler.Aggregator
alias Hologram.Template.VDOM.Expression

defimpl Aggregator, for: Expression do
  def aggregate(%{ir: ir}, module_defs) do
    Aggregator.aggregate(ir, module_defs)
  end
end
