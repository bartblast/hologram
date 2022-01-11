defmodule Hologram.Compiler.Pruner do
  def prune(page_module, module_defs, call_graph) do
    find_reachable_code(page_module, module_defs, call_graph)
    |> remove_redundant_funs(module_defs)
    |> remove_redundant_modules()
  end

  defp find_reachable_code(page_module, module_defs, call_graph) do
    layout_module = page_module.layout()
    component_modules = find_component_modules(module_defs)
    page_modules = find_page_modules(module_defs)

    []
    |> include_code_reachable_from_page_actions(call_graph, page_module)
    |> include_code_reachable_from_page_template(call_graph, page_module)
    |> include_code_reachable_from_page_layout_fun(call_graph, page_module)
    |> include_code_reachable_from_page_custom_layout_fun(call_graph, page_module)
    |> include_code_reachable_from_page_info_fun(call_graph, page_module)
    |> include_code_reachable_from_layout_init_fun(call_graph, layout_module)
    |> include_code_reachable_from_layout_actions(call_graph, layout_module)
    |> include_code_reachable_from_layout_template(call_graph, layout_module)
    |> include_code_reachable_from_component_init_fun(call_graph, component_modules)
    |> include_code_reachable_from_component_actions(call_graph, component_modules)
    |> include_code_reachable_from_component_templates(call_graph, component_modules)
    |> include_page_routes(page_modules)
    |> Enum.uniq()
  end

  defp find_component_modules(module_defs) do
    Enum.filter(module_defs, fn {_, module_def} -> module_def.component? end)
    |> Enum.map(fn {module, _} -> module end)
  end

  defp find_page_modules(module_defs) do
    Enum.filter(module_defs, fn {_, module_def} -> module_def.page? end)
    |> Enum.map(fn {module, _} -> module end)
  end

  defp include_code_reachable_from_component_actions(acc, call_graph, component_modules) do
    Enum.reduce(component_modules, acc, fn module, acc ->
      Graph.reachable(call_graph, [{module, :action}])
      |> maybe_include_reachable_code(acc)
    end)
  end

  defp include_code_reachable_from_component_init_fun(acc, call_graph, component_modules) do
    Enum.reduce(component_modules, acc, fn module, acc ->
      Graph.reachable(call_graph, [{module, :init}])
      |> maybe_include_reachable_code(acc)
    end)
  end

  defp include_code_reachable_from_component_templates(acc, call_graph, component_modules) do
    Enum.reduce(component_modules, acc, fn module, acc ->
      Graph.reachable(call_graph, [{module, :template}])
      |> maybe_include_reachable_code(acc)
    end)
  end

  defp include_code_reachable_from_layout_actions(acc, call_graph, layout_module) do
    Graph.reachable(call_graph, [{layout_module, :action}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_layout_init_fun(acc, call_graph, layout_module) do
    Graph.reachable(call_graph, [{layout_module, :init}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_layout_template(acc, call_graph, layout_module) do
    Graph.reachable(call_graph, [{layout_module, :template}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_page_actions(acc, call_graph, page_module) do
    Graph.reachable(call_graph, [{page_module, :action}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_page_custom_layout_fun(acc, call_graph, page_module) do
    Graph.reachable(call_graph, [{page_module, :custom_layout}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_page_info_fun(acc, call_graph, page_module) do
    Graph.reachable(call_graph, [{page_module, :__info__}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_page_layout_fun(acc, call_graph, page_module) do
    Graph.reachable(call_graph, [{page_module, :layout}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_code_reachable_from_page_template(acc, call_graph, page_module) do
    Graph.reachable(call_graph, [{page_module, :template}])
    |> maybe_include_reachable_code(acc)
  end

  defp include_page_routes(acc, page_modules) do
    Enum.reduce(page_modules, acc, fn module, acc ->
      acc ++ [{module, :route}]
    end)
  end

  defp maybe_include_reachable_code(reachable_code, acc) do
    case reachable_code do
      [nil] ->
        acc

      reachable_code ->
        acc ++ reachable_code
    end
  end

  defp remove_module_redundant_funs(
         %{functions: funs, module: module} = module_def,
         reachable_code_hash_table
       ) do
    funs = Enum.filter(funs, &reachable_code_hash_table[{module, &1.name}])
    %{module_def | functions: funs}
  end

  defp remove_redundant_funs(reachable_code, module_defs) do
    reachable_code_hash_table =
      reachable_code
      |> Enum.map(&{&1, true})
      |> Enum.into(%{})

    Enum.map(module_defs, fn {module, module_def} ->
      {module, remove_module_redundant_funs(module_def, reachable_code_hash_table)}
    end)
    |> Enum.into(%{})
  end

  defp remove_redundant_modules(module_defs) do
    Enum.filter(module_defs, fn {_, module_def} ->
      Enum.any?(module_def.functions)
    end)
    |> Enum.into(%{})
  end
end
