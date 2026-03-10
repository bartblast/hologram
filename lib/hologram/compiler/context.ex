defmodule Hologram.Compiler.Context do
  @moduledoc false

  @type t :: %__MODULE__{
          async?: bool,
          async_mfas: MapSet.t(mfa),
          match_operator?: bool,
          module: module,
          pattern?: bool
        }

  defstruct async?: false,
            async_mfas: MapSet.new(),
            match_operator?: false,
            module: nil,
            pattern?: false
end
