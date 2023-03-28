defmodule Hologram.Compiler.IR do
  @type ir :: IR.AtomType.t() | IR.FloatType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule FloatType do
    defstruct value: nil

    @type t :: %__MODULE__{value: float}
  end
end
