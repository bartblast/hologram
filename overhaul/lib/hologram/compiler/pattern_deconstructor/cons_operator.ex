alias Hologram.Compiler.IR.ConsOperator
alias Hologram.Compiler.IR.ListIndexAccess
alias Hologram.Compiler.IR.ListTailAccess
alias Hologram.Compiler.PatternDeconstructor

defimpl PatternDeconstructor, for: ConsOperator do
  def deconstruct(%{head: head, tail: tail}, path) do
    head_paths = PatternDeconstructor.deconstruct(head, path ++ [%ListIndexAccess{index: 0}])
    tail_paths = PatternDeconstructor.deconstruct(tail, path ++ [%ListTailAccess{}])

    [] ++ head_paths ++ tail_paths
  end
end
