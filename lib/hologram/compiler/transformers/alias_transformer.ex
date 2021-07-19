defmodule Hologram.Compiler.AliasTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Alias

  def transform([{_, _, module_segs}]) do
    module = Helpers.module(module_segs)
    %Alias{module: module, as: [List.last(module_segs)]}
  end

  def transform([{_, _, module_segs}, opts]) do
    module = Helpers.module(module_segs)

    as =
      if Keyword.has_key?(opts, :as) do
        elem(opts[:as], 2)
      else
        [List.last(module_segs)]
      end

    %Alias{module: module, as: as}
  end
end
