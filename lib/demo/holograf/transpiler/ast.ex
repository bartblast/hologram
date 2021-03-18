defmodule Holograf.Transpiler.AST do
  # PRIMITIVES

  defmodule AtomType do
    defstruct value: nil
  end

  defmodule BooleanType do
    defstruct value: nil
  end

  defmodule IntegerType do
    defstruct value: nil
  end

  defmodule StringType do
    defstruct value: nil
  end

  # DATA STRUCTURES

  defmodule MapType do
    defstruct data: nil
  end

  # OTHER

  defmodule Variable do
    defstruct name: nil
  end
end
