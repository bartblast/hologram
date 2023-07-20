defmodule Hologram.Compiler.Pruner do
  # TODO: cleanup

  # alias Hologram.Compiler.CallGraph
  # alias Hologram.Compiler.Reflection

  # def prune(call_graph, entry_module, clone_name) do
  #   call_graph_clone = CallGraph.clone(call_graph, name: clone_name)

  #   if Reflection.page?(entry_module) do
  #     add_action_and_template_edges(call_graph_clone, entry_module, entry_module)

  #     layout_module = entry_module.__hologram_layout_module__()
  #     add_action_and_template_edges(call_graph_clone, entry_module, layout_module)
  #   end

  #   call_graph_clone
  #   |> CallGraph.reachable(entry_module)
  #   |> Enum.filter(&is_tuple/1)
  # end

  # defp add_action_and_template_edges(call_graph, page, to_vertext_module) do
  #   CallGraph.add_edge(call_graph, page, {to_vertext_module, :action, 3})
  #   CallGraph.add_edge(call_graph, page, {to_vertext_module, :template, 0})
  # end
end
