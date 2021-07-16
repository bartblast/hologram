defmodule Hologram.Compiler.AliasTransformer do
  alias Hologram.Compiler.IR.Alias

  def transform([{_, _, module}]) do
    %Alias{module: module, as: [List.last(module)]}
  end

  def transform([{_, _, module}, opts]) do
    as =
      if Keyword.has_key?(opts, :as) do
        elem(opts[:as], 2)
      else
        [List.last(module)]
      end

    %Alias{module: module, as: as}
  end
end
