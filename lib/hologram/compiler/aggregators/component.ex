alias Hologram.Compiler.Aggregator
alias Hologram.Template.VDOM.Component

defimpl Aggregator, for: Component do
  def aggregate(%{module: module, props: props, children: children}, module_defs) do
    module_defs
    |> aggregate_from_module(module)
    |> aggregate_from_props(props)
    |> aggregate_from_children(children)
  end

  defp aggregate_from_children(module_defs, children) do
    Aggregator.aggregate(children, module_defs)
  end

  defp aggregate_from_module(module_defs, module) do
    Aggregator.aggregate(module, module_defs)
  end

  defp aggregate_from_props(module_defs, props) do
    Aggregator.aggregate(props, module_defs)
  end
end
