alias Hologram.Compiler.{Aggregator, Reflection}
alias Hologram.Compiler.IR.ModuleType
alias Hologram.Template.Builder

defimpl Aggregator, for: ModuleType do
  def aggregate(%{module: module}, module_defs) do
    case maybe_put_module(module_defs, module) do
      ^module_defs ->
        module_defs

      new_module_defs ->
        new_module_defs[module].functions
        |> Aggregator.aggregate(new_module_defs)
        |> aggregate_from_template(module)
    end
  end

  defp aggregate_from_template(module_defs, module) do
    if module_defs[module].templatable? do
      Builder.build(module)
      |> Aggregator.aggregate(module_defs)
    else
      module_defs
    end
  end

  defp maybe_put_module(module_defs, module) do
    if module_defs[module] || Reflection.standard_lib?(module) do
      module_defs
    else
      module_def = Reflection.module_definition(module)
      Map.put(module_defs, module, module_def)
    end
  end
end
