defmodule Hologram.Compiler.IR do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  @type data_type_ir ::
          | IR.BinaryType.t()
          | IR.IntegerType.t()
          | IR.ListType.t()
          | IR.MapType.t()
          | IR.ModuleType.t()
          | IR.NilType.t()
          | IR.StringType.t()
          | IR.StructType.t()
          | IR.TupleType.t()

  @type identifier_ir :: IR.Alias.t() | IR.Symbol.t()

  @type operator_ir ::
          IR.AccessOperator.t()
          | IR.AdditionOperator.t()
          | IR.ConsOperator.t()
          | IR.DivisionOperator.t()
          | IR.DotOperator.t()
          | IR.EqualToOperator.t()
          | IR.LessThanOperator.t()
          | IR.ListConcatenationOperator.t()
          | IR.ListSubtractionOperator.t()
          | IR.MatchOperator.t()
          | IR.MembershipOperator.t()
          | IR.ModuleAttributeOperator.t()
          | IR.MultiplicationOperator.t()
          | IR.NotEqualToOperator.t()
          | IR.PinOperator.t()
          | IR.RelaxedBooleanAndOperator.t()
          | IR.RelaxedBooleanNotOperator.t()
          | IR.RelaxedBooleanOrOperator.t()
          | IR.StrictBooleanAndOperator.t()
          | IR.SubtractionOperator.t()
          | IR.TypeOperator.t()

  @type t :: data_type_ir | identifier_ir | operator_ir

  # --- OPERATORS ---

  defmodule AccessOperator do
    defstruct data: nil, key: nil

    @type t :: %__MODULE__{data: IR.t(), key: IR.t()}
  end

  defmodule AdditionOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule ConsOperator do
    defstruct head: nil, tail: nil

    @type t :: %__MODULE__{head: IR.t(), tail: IR.t()}
  end

  defmodule DivisionOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule EqualToOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule LessThanOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule ListConcatenationOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule ListSubtractionOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule MatchOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule MembershipOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  defmodule MultiplicationOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule NotEqualToOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule PinOperator do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  defmodule RelaxedBooleanAndOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule RelaxedBooleanNotOperator do
    defstruct value: nil

    @type t :: %__MODULE__{value: IR.t()}
  end

  defmodule RelaxedBooleanOrOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule StrictBooleanAndOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule SubtractionOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule TypeOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  # --- DATA TYPES ---

  defmodule BinaryType do
    defstruct parts: nil

    @type t :: %__MODULE__{parts: list(IR.t())}
  end

  defmodule IntegerType do
    defstruct value: nil

    @type t :: %__MODULE__{value: integer}
  end

  defmodule ListType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule MapType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list({IR.t(), IR.t()})}
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

    @type t :: %__MODULE__{module: module, data: list({IR.t(), IR.t()})}
  end

  defmodule TupleType do
    defstruct data: nil

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  # --- IDENTIFIERS ---

  defmodule Alias do
    defstruct segments: nil

    @type t :: %__MODULE__{segments: T.alias_segments()}
  end

  defmodule Symbol do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  # --- API ---

  @doc """
  Given Elixir source code returns its Hologram IR.

  ## Examples

      iex> IR.for_code("1 + 2")
      %IR.AdditionOperator{left: %IR.IntegerType{value: 1}, right: %IR.IntegerType{value: 2}}
  """
  @spec for_code(binary) :: IR.t()
  def for_code(code) do
    code
    |> AST.for_code()
    |> Transformer.transform()
  end
end
