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

  # OPERATORS

  defmodule MatchOperator do
    defstruct bindings: nil, left: nil, right: nil
  end

  # ACCESS

  defmodule MapAccess do
    defstruct key: nil
  end

  # C

  defmodule Function do
    defstruct name: nil, args: nil, body: nil
  end

  defmodule Module do
    defstruct name: nil, body: nil
  end

  defmodule Variable do
    defstruct name: nil
  end
end
