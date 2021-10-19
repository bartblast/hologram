alias Hologram.Compiler.{Context, Encoder, Formatter, FunctionDefinitionGenerator, Helpers, Opts}
alias Hologram.Compiler.IR.{ModuleDefinition, NotSupportedExpression}

defimpl Encoder, for: ModuleDefinition do

  def encode(%ModuleDefinition{module: module, attributes: attrs} = ir, %Context{}, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    context = struct(Context, Map.from_struct(ir))

    attrs =
      attrs
      |> Enum.reject(&match?(%NotSupportedExpression{}, &1))
      |> Enum.map(&Encoder.encode(&1, context, opts))
      |> Enum.join("\n")

    functions =
      aggregate_functions(ir)
      |> Enum.map(fn {k, v} -> FunctionDefinitionGenerator.generate(k, v, context, opts) end)
      |> Enum.join("\n")

    "window.#{class_name} = class #{class_name} {"
    |> Formatter.maybe_append_new_section(attrs)
    |> Formatter.maybe_append_new_section(functions)
    |> Formatter.maybe_append_new_line("}")
    |> Formatter.append_line_break()
  end

  defp aggregate_functions(%{functions: functions}) do
    Enum.reduce(functions, %{}, fn fun, acc ->
      if Map.has_key?(acc, fun.name) do
        Map.put(acc, fun.name, acc[fun.name] ++ [fun])
      else
        Map.put(acc, fun.name, [fun])
      end
    end)
  end
end
