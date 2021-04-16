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

  defmodule MatchOperator do
    defstruct bindings: nil, left: nil, right: nil
  end

  # DIRECTIVES

  defmodule Alias do
    defstruct module: nil
  end

  defmodule Import do
    defstruct module: nil
  end

  # OTHER

  defmodule Call do
    defstruct module: nil, function: nil, params: nil
  end

  defmodule Function do
    defstruct name: nil, params: nil, bindings: nil, body: nil
  end

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule Module do
    defstruct name: nil, aliases: nil, functions: nil
  end

  defmodule ModuleAttribute do
    defstruct name: nil
  end

  defmodule Variable do
    defstruct name: nil
  end
end
