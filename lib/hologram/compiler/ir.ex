defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.IR

  @type t ::
          IR.AtomType.t()
          | IR.FloatType.t()
          | IR.IntegerType.t()
          | IR.ListType.t()
          | IR.TupleType.t()

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

  defmodule ListType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule TupleType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end
end
