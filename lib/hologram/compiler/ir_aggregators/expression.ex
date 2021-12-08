alias Hologram.Compiler.IRAggregator
alias Hologram.Template.VDOM.Expression

defimpl IRAggregator, for: Expression do
  def aggregate(%{ir: ir}) do
    IRAggregator.aggregate(ir)
  end
end
