alias Hologram.Compiler.IR.ModuleType
alias Hologram.Compiler.{IRAggregator, IRStore}

defimpl IRAggregator, for: ModuleType do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder

  @ignored_modules [Ecto.Changeset, Hologram.Runtime.JS] ++ Application.get_env(:hologram, :ignored_modules, [])
  @ignored_namespaces Application.get_env(:hologram, :ignored_namespaces, [])

  def aggregate(%{module: module}) do
    if module_def = maybe_put_module(module) do
      aggregate_from_function_defs(module_def.functions)
      |> maybe_aggregate_from_template(module_def)
      |> Enum.map(&(Task.await(&1, :infinity)))
    end
  end

  defp aggregate_from_function_defs(function_defs) do
    function_defs
    |> Enum.map(&(Task.async(fn -> IRAggregator.aggregate(&1) end)))
  end

  defp ignored?(module) do
    if module in @ignored_modules do
      true
    else
      module_name = to_string(module)
      Enum.any?(@ignored_namespaces, fn namespace ->
        String.starts_with?(module_name, to_string(namespace) <> ".")
      end)
    end
  end

  defp maybe_aggregate_from_template(tasks, module_def) do
    if module_def.templatable? do
      task = Task.async(fn ->
         # TODO: use template store here
        TemplateBuilder.build(module_def.module)
        |> IRAggregator.aggregate()
      end)
      [task | tasks]
    else
      tasks
    end
  end

  defp maybe_put_module(module) do
    if IRStore.get(module) || ignored?(module) || Reflection.standard_lib?(module) do
      nil
    else
      module_def = Reflection.module_definition(module)
      IRStore.put(module, module_def)
      module_def
    end
  end
end
