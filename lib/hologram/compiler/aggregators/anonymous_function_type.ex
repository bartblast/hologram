# TODO: test

alias Hologram.Compiler.Aggregator
alias Hologram.Compiler.IR.AnonymousFunctionType

defimpl Aggregator, for: AnonymousFunctionType do
  def aggregate(%{params: params, body: body}, module_defs) do
    module_defs = Aggregator.aggregate(params, module_defs)
    Aggregator.aggregate(body, module_defs)
  end
end
