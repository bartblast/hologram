alias Hologram.Compiler.{Context, Formatter, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.{ModuleDefinition, NotSupportedExpression}

defimpl JSEncoder, for: ModuleDefinition do
  def encode(%{module: module, attributes: attrs, functions: function_defs} = ir, %Context{}, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    context = struct(Context, Map.from_struct(ir))

    attrs =
      attrs
      |> Enum.reject(&match?(%NotSupportedExpression{}, &1))
      |> Enum.map(&JSEncoder.encode(&1, context, opts))
      |> Enum.join("\n")

    functions =
      Helpers.aggregate_function_def_variants(function_defs)
      |> Map.values()
      |> Enum.map(&JSEncoder.encode(&1, context, opts))
      |> Enum.join("\n")

    "window.#{class_name} = class #{class_name} {"
    |> Formatter.maybe_append_new_section(attrs)
    |> Formatter.maybe_append_new_section(functions)
    |> Formatter.maybe_append_new_line("}")
    |> Formatter.append_line_break()
  end
end
