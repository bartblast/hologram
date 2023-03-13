# TODO: test

alias Hologram.Compiler.IR.AnonymousFunctionType
alias Hologram.Compiler.ModuleDefAggregator

defimpl ModuleDefAggregator, for: AnonymousFunctionType do
  def aggregate(%{params: params, body: body}) do
    ModuleDefAggregator.aggregate(params)
    ModuleDefAggregator.aggregate(body)
  end
end
