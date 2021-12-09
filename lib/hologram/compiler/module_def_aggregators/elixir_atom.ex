# TODO: test

alias Hologram.Compiler.{ModuleDefAggregator, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl ModuleDefAggregator, for: Atom do
  def aggregate(module) do
    if Reflection.is_module?(module) do
      %ModuleType{module: module}
      |> ModuleDefAggregator.aggregate()
    end
  end
end
