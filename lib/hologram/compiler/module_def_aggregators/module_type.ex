alias Hologram.Compiler.IR.ModuleType
alias Hologram.Compiler.{ModuleDefAggregator, ModuleDefStore}

defimpl ModuleDefAggregator, for: ModuleType do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Hologram.Utils

  def aggregate(%{module: module}) do
    if module_def = maybe_get_module_def(module) do
      aggregate_from_function_defs(module_def.functions)
      |> maybe_aggregate_from_template(module_def)
      |> Utils.await_tasks()
    end
  end

  defp aggregate_from_function_defs(function_defs) do
    function_defs
    |> Enum.map(&Task.async(fn -> ModuleDefAggregator.aggregate(&1) end))
  end

  defp maybe_aggregate_from_template(tasks, module_def) do
    if module_def.templatable? do
      task =
        Task.async(fn ->
          # TODO: use template store here
          TemplateBuilder.build(module_def.module)
          |> ModuleDefAggregator.aggregate()
        end)

      [task | tasks]
    else
      tasks
    end
  end

  defp maybe_get_module_def(module) do
    if Reflection.is_ignored_module?(module) || Reflection.standard_lib?(module) do
      nil
    else
      ModuleDefStore.get_if_not_exists(module)
    end
  end
end
