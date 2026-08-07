defmodule Hologram.Compiler.Context do
  @moduledoc false

  # arity and function name the definition being encoded, which anonymous
  # functions defined inside it are named after, the way the BEAM names them.
  # guard? marks the guard being encoded - a guard that fails is a guard that
  # didn't hold, never a raise, so its calls record no line.
  @type t :: %__MODULE__{
          arity: non_neg_integer | nil,
          async?: bool,
          async_mfas: MapSet.t(mfa),
          function: atom | nil,
          guard?: bool,
          match_operator?: bool,
          module: module,
          pattern?: bool
        }

  defstruct arity: nil,
            async?: false,
            async_mfas: MapSet.new(),
            function: nil,
            guard?: false,
            match_operator?: false,
            module: nil,
            pattern?: false
end
