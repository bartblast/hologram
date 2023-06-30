defmodule Hologram.Compiler.Context do
  @type t :: %__MODULE__{
          match_operator?: bool,
          module: module,
          pattern?: bool,
          use_vars_snapshot?: bool
        }

  defstruct match_operator?: false, module: nil, pattern?: false, use_vars_snapshot?: false
end
