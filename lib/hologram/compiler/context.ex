defmodule Hologram.Compiler.Context do
  @type t :: %__MODULE__{pattern?: bool}

  defstruct pattern?: false
end
