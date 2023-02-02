defmodule Hologram.Compiler.UseDirectiveTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  def transform({:use, _, [{_, _, alias_segs}]}) do
    %IR.UseDirective{alias_segs: alias_segs, opts: []}
  end

  def transform({:use, _, [{_, _, alias_segs}, opts]}) do
    new_opts =
      Enum.map(opts, fn {key, value} ->
        {key, Transformer.transform(value, %Context{})}
      end)

    %IR.UseDirective{alias_segs: alias_segs, opts: new_opts}
  end
end
