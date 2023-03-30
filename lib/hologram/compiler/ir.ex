defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.IR

  @type t :: IR.AtomType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end
end
