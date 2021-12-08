# TODO: test

alias Hologram.Compiler.IR.AnonymousFunctionType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: AnonymousFunctionType do
  def aggregate(%{params: params, body: body}) do
    IRAggregator.aggregate(params)
    IRAggregator.aggregate(body)
  end
end
