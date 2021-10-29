alias Hologram.Compiler.{Aggregator, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl Aggregator, for: ModuleType do
  def aggregate(%{module: module}, module_defs) do
    case maybe_add(module_defs, module) do
      ^module_defs ->
        module_defs

      new_module_defs ->
        new_module_defs[module].functions
        |> Aggregator.aggregate(new_module_defs)
    end
  end

  defp maybe_add(module_defs, module) do
    unless module_defs[module] || Reflection.standard_lib?(module) do
      module_def = Reflection.module_definition(module)
      Map.put(module_defs, module, module_def)
    else
      module_defs
    end
  end
end
