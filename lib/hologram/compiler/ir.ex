defmodule Hologram.Compiler.IR do
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

  defmodule NilType do
    defstruct []
  end

  defmodule StringType do
    defstruct value: nil
  end

  defmodule TupleType do
    defstruct data: []
  end
end
