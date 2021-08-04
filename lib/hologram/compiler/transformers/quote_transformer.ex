defmodule Hologram.Compiler.QuoteTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.Quote

  def transform({:quote, _, [[do: {:__block__, [], body}]]}, %Context{} = context) do
    body = Enum.map(body, &Transformer.transform(&1, context))
    %Quote{body: body}
  end
end
