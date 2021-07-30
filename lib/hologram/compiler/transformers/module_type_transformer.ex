defmodule Hologram.Compiler.ModuleTypeTransformer do
  alias Hologram.Compiler.{Context, Resolver}
  alias Hologram.Compiler.IR.ModuleType

  def transform(module_segs, %Context{} = context) do
    module = Resolver.resolve(module_segs, context.aliases)
    %ModuleType{module: module}
  end
end
