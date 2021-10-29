alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.ModuleType

# TODO: test
defimpl Aggregator, for: ModuleType do
  def traverse(%{module: module}, module_defs) do
    case maybe_add_module_def(module_defs, module) do
      ^module_defs ->
        module_defs

      new_module_defs ->
        new_module_defs[module].functions
        |> Enum.reduce(new_module_defs, &Aggregator.aggregate/2)
    end
  end

  defp maybe_add_module_def(module_defs, module) do
    unless module_defs[module] || Reflection.standard_lib?(module) do
      module_def = Reflection.module_definition(module)
      Map.put(module_defs, module, module_def)
    else
      module_defs
    end
  end
end
