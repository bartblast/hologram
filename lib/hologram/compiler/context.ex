defmodule Hologram.Compiler.Context do
  @enforce_keys [:module, :imports, :aliases]
  defstruct @enforce_keys
end
