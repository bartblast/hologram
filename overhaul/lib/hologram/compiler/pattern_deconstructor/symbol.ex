alias Hologram.Compiler.IR.Symbol
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: Symbol do
  def deconstruct(symbol, path) do
    [path ++ [symbol]]
  end
end
