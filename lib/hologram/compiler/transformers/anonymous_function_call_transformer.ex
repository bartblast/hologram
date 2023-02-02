defmodule Hologram.Compiler.AnonymousFunctionCallTransformer do
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [{name, _, _}]}, _, args}) do
    %AnonymousFunctionCall{
      name: name,
      args: Enum.map(args, &Transformer.transform/1)
    }
  end
end
