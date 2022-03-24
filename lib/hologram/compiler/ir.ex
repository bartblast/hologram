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
    defstruct data: nil, key: nil
  end

  defmodule AdditionOperator do
    defstruct left: nil, right: nil
  end

  defmodule DivisionOperator do
    defstruct left: nil, right: nil
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil
  end

  defmodule EqualToOperator do
    defstruct left: nil, right: nil
  end

  defmodule ListConcatenationOperator do
    defstruct left: nil, right: nil
  end

  defmodule ListSubtractionOperator do
    defstruct left: nil, right: nil
  end

  defmodule MatchOperator do
    defstruct bindings: [], left: nil, right: nil
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil
  end

  defmodule MultiplicationOperator do
    defstruct left: nil, right: nil
  end

  defmodule RelaxedBooleanAndOperator do
    defstruct left: nil, right: nil
  end

  defmodule RelaxedBooleanOrOperator do
    defstruct left: nil, right: nil
  end

  defmodule StrictBooleanAndOperator do
    defstruct left: nil, right: nil
  end

  defmodule SubtractionOperator do
    defstruct left: nil, right: nil
  end

  defmodule TypeOperator do
    defstruct left: nil, right: nil
  end

  defmodule UnaryNegativeOperator do
    defstruct value: nil
  end

  defmodule UnaryPositiveOperator do
    defstruct value: nil
  end

  # DEFINITIONS

  defmodule FunctionDefinition do
    defstruct module: nil,
              name: nil,
              arity: nil,
              params: [],
              bindings: [],
              body: [],
              visibility: nil
  end

  defmodule FunctionDefinitionVariants do
    defstruct name: nil, variants: []
  end

  # DEFER: implement
  defmodule FunctionHead do
    defstruct []
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
              macros: [],
              component?: nil,
              layout?: nil,
              page?: nil,
              templatable?: nil
  end

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, value: nil
  end

  # DEFER: implement
  defmodule ProtocolDefinition do
    defstruct []
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
    defstruct module: nil, opts: []
  end

  # CONTROL FLOW

  defmodule CaseExpression do
    defstruct condition: nil, clauses: []
  end

  defmodule IfExpression do
    defstruct condition: nil, do: nil, else: nil, ast: nil
  end

  # BINDINGS

  defmodule Binding do
    defstruct name: nil, access_path: []
  end

  defmodule CaseConditionAccess do
    defstruct []
  end

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule MatchAccess do
    defstruct []
  end

  defmodule ParamAccess do
    defstruct index: nil
  end

  defmodule TupleAccess do
    defstruct index: nil
  end

  # OTHER

  defmodule Block do
    defstruct expressions: []
  end

  defmodule FunctionCall do
    defstruct module: nil, function: nil, args: []
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

  defmodule Typespec do
    defstruct []
  end

  defmodule Variable do
    defstruct name: nil
  end

  # NOT SUPPORTED

  defmodule NotSupportedExpression do
    defstruct ast: nil, type: nil
  end
end
