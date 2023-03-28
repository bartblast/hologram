defmodule Hologram.Compiler.IR do
  @type ir ::
          IR.AtomType.t()
          | IR.FloatType.t()
          | IR.IntegerType.t()
          | IR.ListType.t()
          | IR.ModuleAttributeDefinition.t()
          | IR.ModuleAttributeOperator.t()
          | IR.Symbol.t()
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

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, expression: nil

    @type t :: %__MODULE__{name: atom, expression: IR.t()}
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  defmodule Symbol do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  defmodule TupleType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end
end
