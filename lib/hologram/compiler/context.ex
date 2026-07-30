defmodule Hologram.Compiler.Context do
  @moduledoc false

  # arity and function name the definition being encoded, which anonymous
  # functions defined inside it are named after, the way the BEAM names them.
  @type t :: %__MODULE__{
          arity: non_neg_integer | nil,
          async?: bool,
          async_mfas: MapSet.t(mfa),
          function: atom | nil,
          match_operator?: bool,
          module: module,
          pattern?: bool
        }

  defstruct arity: nil,
            async?: false,
            async_mfas: MapSet.new(),
            function: nil,
            match_operator?: false,
            module: nil,
            pattern?: false
end
