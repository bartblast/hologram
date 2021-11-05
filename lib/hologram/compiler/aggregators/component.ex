alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.ModuleType
alias Hologram.Template.VDOM.Component

defimpl Aggregator, for: Component do
  def aggregate(%{module: module, props: props, children: children}, module_defs) do
    aggregate_from_module(module_defs, module)
    |> aggregate_from_props(props)
    |> aggregate_from_children(children)
  end

  defp aggregate_from_children(module_defs, children) do
    Aggregator.aggregate(children, module_defs)
  end

  defp aggregate_from_module(module_defs, module) do
    %ModuleType{module: module}
    |> Aggregator.aggregate(module_defs)
  end

  defp aggregate_from_props(module_defs, props) do
    Aggregator.aggregate(props, module_defs)
  end
end
