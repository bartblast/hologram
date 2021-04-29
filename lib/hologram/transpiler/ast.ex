defmodule Hologram.Transpiler.AST do
  # TYPES

  defmodule AtomType do
    defstruct value: nil
  end

  defmodule BooleanType do
    defstruct value: nil
  end

  defmodule IntegerType do
    defstruct value: nil
  end

  defmodule ListType do
    defstruct data: nil
  end

  defmodule MapType do
    defstruct data: nil
  end

  defmodule StringType do
    defstruct value: nil
  end

  defmodule StructType do
    defstruct module: nil, data: nil
  end

  # OPERATORS

  defmodule AdditionOperator do
    defstruct left: nil, right: nil
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil
  end

  defmodule MatchOperator do
    defstruct bindings: nil, left: nil, right: nil
  end

  # DIRECTIVES

  defmodule Alias do
    defstruct module: nil, as: nil
  end

  defmodule Import do
    defstruct module: nil, only: nil
  end

  # OTHER

  defmodule Function do
    defstruct name: nil, arity: nil, params: nil, bindings: nil, body: nil
  end

  defmodule FunctionCall do
    defstruct module: nil, function: nil, params: nil
  end

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule Module do
    defstruct name: nil, imports: nil, aliases: nil, functions: nil
  end

  defmodule ModuleAttribute do
    defstruct name: nil
  end

  defmodule Variable do
    defstruct name: nil
  end
end
