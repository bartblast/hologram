# TODO: test

alias Hologram.Compiler.{CallGraphBuilder, Reflection}
alias Hologram.Compiler.IR.ModuleType

defimpl CallGraphBuilder, for: Atom do
  def build(ir, module_defs, templates, from_vertex) do
    if Reflection.is_module?(ir) do
      %ModuleType{module: ir}
      |> CallGraphBuilder.build(module_defs, templates, from_vertex)
    end
  end
end
