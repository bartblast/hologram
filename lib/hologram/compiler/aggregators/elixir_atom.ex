# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.ModuleType

defimpl Aggregator, for: Atom do
  def aggregate(module, module_defs) do
    %ModuleType{module: module}
    |> Aggregator.aggregate(module_defs)
  end
end
