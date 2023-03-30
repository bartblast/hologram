defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.IR

  @type t :: IR.AtomType.t() | IR.FloatType.t() | IR.IntegerType.t()

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule FloatType do
    defstruct value: nil

    @type t :: %__MODULE__{value: float}
  end

  defmodule IntegerType do
    defstruct value: nil

    @type t :: %__MODULE__{value: integer}
  end
end
