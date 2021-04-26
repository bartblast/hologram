defmodule Hologram.Compiler do
  alias Hologram.Transpiler.Helpers
  alias Hologram.Transpiler.Normalizer
  alias Hologram.Transpiler.Parser
  alias Hologram.Transpiler.Transformer

  def compile(module, acc \\ %{}) do
    fully_qualified_module = Helpers.fully_qualified_module(module)
    source = fully_qualified_module.module_info()[:compile][:source]

    module_ast =
      Parser.parse_file!(source)
      |> Normalizer.normalize()
      |> Transformer.transform()

    Map.put(acc, module, module_ast)
    |> compile_directives(module_ast, :imports)
    |> compile_directives(module_ast, :aliases)
  end

  defp compile_directives(acc, current_module, directive_key) do
    Map.get(current_module, directive_key)
    |> Enum.reduce(acc, fn directive, acc ->
      if Map.has_key?(acc, directive.module) do
        acc
      else
        compile(directive.module, acc)
      end
    end)
  end
end
