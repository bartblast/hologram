defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Transformer

  def transform({:defmodule, _, [module, [do: body]]}) do
    %ModuleDefinition{
      module: Transformer.transform(module),
      body: Transformer.transform(body)
    }
  end
end
