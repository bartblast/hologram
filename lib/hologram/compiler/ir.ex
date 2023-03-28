defmodule Hologram.Compiler.IR do
  @type ir :: IR.AtomType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end
end
