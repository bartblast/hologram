defmodule Hologram.Compiler.ModuleDefinitionGenerator do
  alias Hologram.Compiler.{
    Context,
    Formatter,
    FunctionDefinitionGenerator,
    Generator,
    Helpers,
    Opts
  }

  alias Hologram.Compiler.IR.NotSupportedExpression

  def generate(ir, module, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    context = struct(Context, Map.from_struct(ir))

    attributes =
      ir.attributes
      |> Enum.reject(&match?(%NotSupportedExpression{}, &1))
      |> Enum.map(&Generator.generate(&1, context, opts))
      |> Enum.join("\n")

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context, opts) end)
      |> Enum.join("\n")

    "window.#{class_name} = class #{class_name} {"
    |> Formatter.maybe_append_new_section(attributes)
    |> Formatter.maybe_append_new_section(functions)
    |> Formatter.maybe_append_new_line("}")
    |> Formatter.append_line_break()
  end

  defp aggregate_functions(ir) do
    Enum.reduce(ir.functions, %{}, fn fun, acc ->
      if Map.has_key?(acc, fun.name) do
        Map.put(acc, fun.name, acc[fun.name] ++ [fun])
      else
        Map.put(acc, fun.name, [fun])
      end
    end)
  end
end
