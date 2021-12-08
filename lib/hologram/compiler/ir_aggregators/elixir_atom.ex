# TODO: test

alias Hologram.Compiler.{IRAggregator, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl IRAggregator, for: Atom do
  def aggregate(module) do
    if Reflection.is_module?(module) do
      %ModuleType{module: module}
      |> IRAggregator.aggregate()
    end
  end
end
