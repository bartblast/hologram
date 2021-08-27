defmodule Hologram.Compiler.ModuleTypeTransformer do
  alias Hologram.Compiler.{Context, Resolver}
  alias Hologram.Compiler.IR.ModuleType

  def transform({:__aliases__, _, module_segs}, %Context{} = context) do
    module = Resolver.resolve(module_segs, context.aliases)
    %ModuleType{module: module}
  end

  def transform(module, _), do: %ModuleType{module: module}
end
