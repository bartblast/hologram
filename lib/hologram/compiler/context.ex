defmodule Hologram.Compiler.Context do
  @enforce_keys [:module, :uses, :imports, :aliases, :attributes]
  defstruct @enforce_keys
end
