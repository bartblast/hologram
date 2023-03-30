defmodule Hologram.Compiler.IR do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.IR

  @type t ::
          IR.AnonymousFunctionCall.t()
          | IR.AtomType.t()
          | IR.DotOperator.t()
          | IR.FloatType.t()
          | IR.IntegerType.t()
          | IR.ListType.t()
          | IR.LocalFunctionCall.t()
          | IR.ModuleType.t()
          | IR.TupleType.t()
          | IR.Variable.t()

  defmodule AnonymousFunctionCall do
    defstruct function: nil, args: nil

    @type t :: %__MODULE__{function: IR.t(), args: list(IR.t())}
  end

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
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

  defmodule LocalFunctionCall do
    defstruct function: nil, args: nil

    @type t :: %__MODULE__{function: atom, args: list(IR.t())}
  end

  defmodule ModuleType do
    defstruct module: nil, segments: nil

    @type t :: %__MODULE__{module: module, segments: T.alias_segments()}
  end

  defmodule TupleType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule Variable do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end
end
