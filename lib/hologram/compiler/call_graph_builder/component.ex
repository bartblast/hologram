# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.ModuleType
alias Hologram.Template.VDOM.Component

defimpl CallGraphBuilder, for: Component do
  def build(%{module: module, props: props, children: children}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(%ModuleType{module: module}, module_defs, templates, from_vertex)
    CallGraphBuilder.build(props, module_defs, templates, from_vertex)
    CallGraphBuilder.build(children, module_defs, templates, from_vertex)
  end
end
