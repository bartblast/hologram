defmodule Hologram.Compiler.IR do
  # TYPES

  defmodule AnonymousFunctionType do
    defstruct arity: nil, params: [], bindings: [], body: []
  end

  defmodule AtomType do
    defstruct value: nil
  end

  defmodule BinaryType do
    defstruct parts: []
  end

  defmodule BooleanType do
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
    defstruct module: nil
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

  # OPERATORS

  defmodule AccessOperator do
    defstruct key: nil
  end

  defmodule AdditionOperator do
    defstruct left: nil, right: nil
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil
  end

  defmodule EqualToOperator do
    defstruct left: nil, right: nil
  end

  defmodule MatchOperator do
    defstruct bindings: [], left: nil, right: nil
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil
  end

  defmodule TypeOperator do
    defstruct left: nil, right: nil
  end

  # DEFINITIONS

  defmodule FunctionDefinition do
    defstruct name: nil, arity: nil, params: [], bindings: [], body: []
  end

  defmodule FunctionDefinitionVariants do
    defstruct name: nil, variants: []
  end

  defmodule MacroDefinition do
    defstruct module: nil, name: nil, arity: nil, params: [], bindings: [], body: []
  end

  defmodule ModuleDefinition do
    defstruct module: nil,
              uses: [],
              imports: [],
              requires: [],
              aliases: [],
              attributes: [],
              functions: [],
              macros: []
  end

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, value: nil
  end

  # DIRECTIVES

  defmodule AliasDirective do
    defstruct module: nil, as: nil
  end

  defmodule ImportDirective do
    defstruct module: nil, only: nil
  end

  defmodule RequireDirective do
    defstruct module: nil
  end

  defmodule UseDirective do
    defstruct module: nil
  end

  # CONTROL FLOW

  defmodule IfExpression do
    defstruct condition: nil, do: nil, else: nil
  end

  # OTHER

  defmodule FunctionCall do
    defstruct module: nil, function: nil, params: []
  end

  defmodule Quote do
    defstruct body: []
  end

  defmodule ModulePseudoVariable do
    defstruct []
  end

  defmodule Unquote do
    defstruct expression: nil
  end

  defmodule Variable do
    defstruct name: nil
  end

  # NOT SUPPORTED

  defmodule NotSupportedExpression do
    defstruct ast: nil, type: nil
  end
end
