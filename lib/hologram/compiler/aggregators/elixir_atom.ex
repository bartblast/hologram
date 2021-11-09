# TODO: test

alias Hologram.Compiler.{Aggregator, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl Aggregator, for: Atom do
  def aggregate(module, module_defs) do
    if Reflection.is_module?(module) do
      %ModuleType{module: module}
      |> Aggregator.aggregate(module_defs)
    else
      module_defs
    end
  end
end
