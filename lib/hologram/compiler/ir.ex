defmodule Hologram.Compiler.IR do
  # TYPES

  defmodule AnonymousFunctionType do
    defstruct arity: nil, params: [], bindings: [], body: nil
  end

  defmodule AtomType do
    defstruct value: nil, kind: :basic_data_type
  end

  defmodule BinaryType do
    defstruct parts: []
  end

  defmodule BooleanType do
    defstruct value: nil, kind: :basic_data_type
  end

  defmodule FloatType do
    defstruct value: nil, kind: :basic_data_type
  end

  defmodule IntegerType do
    defstruct value: nil, kind: :basic_data_type
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
    defstruct value: nil, kind: :basic_data_type
  end

  defmodule StructType do
    defstruct alias_segs: nil, module: nil, data: []
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

  defmodule ConsOperator do
    defstruct head: nil, tail: nil
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

  defmodule LessThanOperator do
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

  defmodule MembershipOperator do
    defstruct left: nil, right: nil
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil
  end

  defmodule MultiplicationOperator do
    defstruct left: nil, right: nil
  end

  defmodule NotEqualToOperator do
    defstruct left: nil, right: nil
  end

  defmodule RelaxedBooleanAndOperator do
    defstruct left: nil, right: nil
  end

  defmodule RelaxedBooleanNotOperator do
    defstruct value: nil
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
              body: nil,
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
    defstruct module: nil, name: nil, arity: nil, params: [], bindings: [], body: nil
  end

  defmodule ModuleDefinition do
    defstruct module: nil, body: nil
  end

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, expression: nil
  end

  # DEFER: implement
  defmodule ProtocolDefinition do
    defstruct []
  end

  # DIRECTIVES

  defmodule AliasDirective do
    defstruct alias_segs: nil, as: nil
  end

  defmodule ImportDirective do
    defstruct alias_segs: nil, only: [], except: []
  end

  defmodule RequireDirective do
    defstruct alias_segs: nil, module: nil
  end

  defmodule UseDirective do
    defstruct alias_segs: nil, module: nil, opts: []
  end

  # CONTROL FLOW

  defmodule AnonymousFunctionCall do
    defstruct name: nil, args: []
  end

  defmodule Call do
    defstruct module: nil, function: nil, args: []
  end

  defmodule CaseExpression do
    defstruct condition: nil, clauses: []
  end

  defmodule FunctionCall do
    defstruct module: nil, function: nil, args: []
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

  defmodule ListIndexAccess do
    defstruct index: nil
  end

  defmodule ListTailAccess do
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

  defmodule Alias do
    defstruct segments: nil
  end

  defmodule Block do
    defstruct expressions: []
  end

  defmodule IgnoredExpression do
    defstruct []
  end

  defmodule ModulePseudoVariable do
    defstruct []
  end

  defmodule Quote do
    defstruct body: nil
  end

  defmodule Symbol do
    defstruct name: nil
  end

  defmodule Typespec do
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
