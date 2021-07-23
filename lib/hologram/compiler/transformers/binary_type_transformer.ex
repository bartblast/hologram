defmodule Hologram.Compiler.BinaryTypeTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.BinaryType

  def transform(parts, %Context{} = context) do
    parts = Enum.map(parts, &Transformer.transform(&1, context))
    %BinaryType{parts: parts}
  end
end
