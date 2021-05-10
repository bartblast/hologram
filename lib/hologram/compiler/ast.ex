defmodule Hologram.Compiler.AST do
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

  defmodule ModuleAttributeOperator do
    defstruct name: nil
  end

  # DEFINITIONS

  defmodule FunctionDefinition do
    defstruct name: nil, arity: nil, params: nil, bindings: nil, body: nil
  end

  defmodule ModuleDefinition do
    defstruct name: nil, imports: nil, aliases: nil, attributes: nil, functions: nil
  end

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, value: nil
  end

  # DIRECTIVES

  defmodule Alias do
    defstruct module: nil, as: nil
  end

  defmodule Import do
    defstruct module: nil, only: nil
  end

  # OTHER

  defmodule FunctionCall do
    defstruct module: nil, function: nil, params: nil
  end

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule Variable do
    defstruct name: nil
  end
end
