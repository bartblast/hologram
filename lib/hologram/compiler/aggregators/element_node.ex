alias Hologram.Compiler.Aggregator
alias Hologram.Template.VDOM.ElementNode

defimpl Aggregator, for: ElementNode do
  def aggregate(%{attrs: attrs, children: children}, module_defs) do
    aggregate_from_attrs(module_defs, attrs)
    |> aggregate_from_children(children)
  end

  defp aggregate_from_attrs(module_defs, attrs) do
    Aggregator.aggregate(attrs, module_defs)
  end

  defp aggregate_from_children(module_defs, children) do
    Aggregator.aggregate(children, module_defs)
  end
end
