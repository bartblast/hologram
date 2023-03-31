defmodule Hologram.Compiler.IR do
  @type data_type_ir ::
          | IR.BinaryType.t()
          | IR.StringType.t()
          | IR.StructType.t()

  @type operator_ir ::
          IR.AccessOperator.t()
          | IR.AdditionOperator.t()
          | IR.DivisionOperator.t()
          | IR.EqualToOperator.t()
          | IR.LessThanOperator.t()
          | IR.ListConcatenationOperator.t()
          | IR.ListSubtractionOperator.t()
          | IR.MatchOperator.t()
          | IR.MembershipOperator.t()
          | IR.MultiplicationOperator.t()
          | IR.NotEqualToOperator.t()
          | IR.PinOperator.t()
          | IR.RelaxedBooleanAndOperator.t()
          | IR.RelaxedBooleanNotOperator.t()
          | IR.RelaxedBooleanOrOperator.t()
          | IR.StrictBooleanAndOperator.t()
          | IR.SubtractionOperator.t()
          | IR.TypeOperator.t()

  @type t :: data_type_ir | operator_ir

  # --- OPERATORS ---

  defmodule AccessOperator do
    defstruct data: nil, key: nil

    @type t :: %__MODULE__{data: IR.t(), key: IR.t()}
  end

  defmodule AdditionOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule DivisionOperator do
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

  defmodule StringType do
    defstruct value: nil

    @type t :: %__MODULE__{value: binary}
  end

  defmodule StructType do
    defstruct module: nil, data: nil

    @type t :: %__MODULE__{module: module, data: list({IR.t(), IR.t()})}
  end
end
