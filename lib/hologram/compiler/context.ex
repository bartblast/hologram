defmodule Hologram.Compiler.Context do
  @moduledoc false

  alias Hologram.Commons.PLT

  # arity and function name the definition being encoded, which anonymous
  # functions defined inside it are named after, the way the BEAM names them.
  # guard? marks the guard being encoded - a guard that fails is a guard that
  # didn't hold, never a raise, so its calls record no line.
  # ir_plt is the IR PLT of the compile being encoded, when there is one; it answers
  # which modules are Elixir modules without consulting their code path.
  @type t :: %__MODULE__{
          arity: non_neg_integer | nil,
          async?: bool,
          async_mfas: MapSet.t(mfa),
          function: atom | nil,
          guard?: bool,
          ir_plt: PLT.t() | nil,
          match_operator?: bool,
          module: module,
          pattern?: bool
        }

  defstruct arity: nil,
            async?: false,
            async_mfas: MapSet.new(),
            function: nil,
            guard?: false,
            ir_plt: nil,
            match_operator?: false,
            module: nil,
            pattern?: false
end
