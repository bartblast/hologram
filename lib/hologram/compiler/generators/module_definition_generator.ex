defmodule Hologram.Compiler.ModuleDefinitionGenerator do
  alias Hologram.Compiler.{Context, Formatter, FunctionDefinitionGenerator, Generator, Helpers, Opts}

  def generate(ir, module, %Context{} = context, %Opts{} = opts) do
    class = Helpers.class_name(module)

    attributes =
      Enum.map(ir.attributes, &Generator.generate(&1, context, opts))
      |> Enum.join("\n")

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context, opts) end)
      |> Enum.join("\n")

    "window.#{class} = class #{class} {"
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
