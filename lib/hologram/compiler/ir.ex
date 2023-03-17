defmodule Hologram.Compiler.IR do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Transformer

  @type non_expanded_ir ::
          __MODULE__.AtomType.t()
          | __MODULE__.BinaryType.t()
          | __MODULE__.BooleanType.t()
          | __MODULE__.FloatType.t()
          | __MODULE__.IntegerType.t()
          | __MODULE__.ListType.t()
          | __MODULE__.MapType.t()
          | __MODULE__.ModuleType.t()
          | __MODULE__.NilType.t()
          | __MODULE__.StringType.t()
          | __MODULE__.StructType.t()
          | __MODULE__.TupleType.t()

  # --- OPERATORS ---

  defmodule AdditionOperator do
    defstruct left: nil, right: nil
  end

  defmodule ConsOperator do
    defstruct head: nil, tail: nil
  end

  defmodule MatchOperator do
    defstruct left: nil, right: nil
  end

  # --- DATA TYPES ---

  defmodule AtomType do
    defstruct value: nil

    @type t :: %__MODULE__{value: atom}
  end

  defmodule BinaryType do
    defstruct parts: nil

    @type t :: %__MODULE__{parts: list}
  end

  defmodule BooleanType do
    defstruct value: nil

    @type t :: %__MODULE__{value: boolean}
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

    @type t :: %__MODULE__{data: list}
  end

  defmodule MapType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(tuple)}
  end

  defmodule ModuleType do
    defstruct module: nil, segments: nil

    @type t :: %__MODULE__{module: module, segments: T.alias_segments()}
  end

  defmodule NilType do
    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule StringType do
    defstruct value: nil

    @type t :: %__MODULE__{value: binary}
  end

  defmodule StructType do
    defstruct module: nil, data: nil

    @type t :: %__MODULE__{module: module, data: list(tuple)}
  end

  defmodule TupleType do
    defstruct data: nil

    @type t :: %__MODULE__{data: tuple}
  end

  # --- CONTROL FLOW ---

  defmodule Alias do
    defstruct segments: nil
  end

  defmodule Symbol do
    defstruct name: nil
  end

  # --- API ---

  @doc """
  Given Elixir source code returns its Hologram IR.

  ## Examples

      iex> IR.for_code("1 + 2")
      %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
  """
  def for_code(code) do
    code
    |> AST.for_code()
    |> Transformer.transform()
  end
end
