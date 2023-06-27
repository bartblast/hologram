defmodule Hologram.Compiler.Context do
  @type t :: %__MODULE__{match_operator?: bool, module: module, pattern?: bool}

  defstruct match_operator?: false, module: nil, pattern?: false
end
