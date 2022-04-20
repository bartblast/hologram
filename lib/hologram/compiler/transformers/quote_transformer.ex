defmodule Hologram.Compiler.QuoteTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.Quote

  def transform({:quote, _, [[do: body]]}, %Context{} = context) do
    body = Transformer.transform(body, context)
    %Quote{body: body}
  end
end
