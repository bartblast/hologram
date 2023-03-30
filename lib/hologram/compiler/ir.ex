defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.IR

  @type t :: IR.AtomType.t() | IR.FloatType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule FloatType do
    defstruct value: nil

    @type t :: %__MODULE__{value: float}
  end
end
