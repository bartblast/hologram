defmodule Hologram.Compiler.IR do
  # --- OPERATORS ---

  defmodule ConsOperator do
    defstruct head: nil, tail: nil
  end

  defmodule MatchOperator do
    defstruct left: nil, right: nil
  end

  # --- DATA TYPES ---

  defmodule AtomType do
    defstruct value: nil
  end

  defmodule BinaryType do
    defstruct parts: []
  end

  defmodule BooleanType do
    defstruct value: nil
  end

  defmodule FloatType do
    defstruct value: nil
  end

  defmodule IntegerType do
    defstruct value: nil
  end

  defmodule ListType do
    defstruct data: []
  end

  defmodule MapType do
    defstruct data: []
  end

  defmodule ModuleType do
    defstruct module: nil, segments: nil
  end

  defmodule NilType do
    defstruct []
  end

  defmodule StringType do
    defstruct value: nil
  end

  defmodule StructType do
    defstruct module: nil, data: []
  end

  defmodule TupleType do
    defstruct data: []
  end

  # --- CONTROL FLOW ---

  defmodule Alias do
    defstruct segments: nil
  end

  defmodule Symbol do
    defstruct name: nil
  end
end
