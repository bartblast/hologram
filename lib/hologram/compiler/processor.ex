defmodule Hologram.Compiler.Processor do
  alias Hologram.Compiler.{Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(T.module_segments, map()) :: T.modules_map

  def compile(module, acc \\ %{}) do
    module_definition =
      Helpers.module_source_path(module)
      |> Parser.parse_file!()
      |> Normalizer.normalize()
      |> Transformer.transform()

    Map.put(acc, module, module_definition)
    |> compile_referenced_modules(module_definition, :imports)
    |> compile_referenced_modules(module_definition, :aliases)
  end

  @doc """
  Compiles modules which are referenced by directives of a specific type.
  """
  @spec compile_referenced_modules(T.modules_map, %ModuleDefinition{}, :aliases | :imports) :: T.modules_map
  
  defp compile_referenced_modules(acc, module_definition, directive_type) do
    Map.get(module_definition, directive_type)
    |> Enum.reduce(acc, fn directive, acc ->
      if Map.has_key?(acc, directive.module) do
        acc
      else
        compile(directive.module, acc)
      end
    end)
  end
end
