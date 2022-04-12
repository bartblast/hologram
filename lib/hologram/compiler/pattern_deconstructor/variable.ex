alias Hologram.Compiler.IR.Variable
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: Variable do
  def deconstruct(var, path) do
    [path ++ [var]]
  end
end
