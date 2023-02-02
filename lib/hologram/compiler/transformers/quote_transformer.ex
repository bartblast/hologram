defmodule Hologram.Compiler.QuoteTransformer do
  alias Hologram.Compiler.IR.Quote
  alias Hologram.Compiler.Transformer

  def transform({:quote, _, [[do: body]]}) do
    body = Transformer.transform(body)
    %Quote{body: body}
  end
end
