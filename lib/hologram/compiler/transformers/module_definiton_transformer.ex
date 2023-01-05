defmodule Hologram.Compiler.ModuleDefinitionTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.Transformer

  def transform({:defmodule, _, [module, [do: body]]}, %Context{} = context) do
    %ModuleDefinition{
      module: Transformer.transform(module, context),
      body: Transformer.transform(body, context)
    }
  end
end
