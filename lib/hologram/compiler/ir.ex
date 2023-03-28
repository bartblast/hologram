defmodule Hologram.Compiler.IR do
  @type ir :: IR.AtomType.t() | IR.BooleanType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule BooleanType do
    defstruct value: nil

    @type t :: %__MODULE__{value: boolean}
  end
end
