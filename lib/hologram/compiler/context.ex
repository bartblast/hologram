defmodule Hologram.Compiler.Context do
  @type t :: %__MODULE__{module: module, pattern?: bool}

  defstruct module: nil, pattern?: false
end
