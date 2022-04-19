defmodule Hologram.Compiler.AnonymousFunctionCallTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.AnonymousFunctionCall

  def transform({{:., _, [{name, _, nil}]}, _, args}, %Context{} = context) do
    %AnonymousFunctionCall{
      name: name,
      args: Enum.map(args, &Transformer.transform(&1, context))
    }
  end
end
