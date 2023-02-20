defmodule Hologram.Compiler.IR do
  # --- OPERATORS ---

  defmodule AccessOperator do
    defstruct data: nil, key: nil
  end

  defmodule AdditionOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule ConsOperator do
    defstruct head: nil, tail: nil
  end

  defmodule DivisionOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule ListConcatenationOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule ListSubtractionOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule MatchOperator do
    defstruct bindings: [], left: nil, right: nil
  end

  defmodule MembershipOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil
  end

  defmodule MultiplicationOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule NotEqualToOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule RelaxedBooleanAndOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule RelaxedBooleanNotOperator do
    defstruct value: nil
  end

  defmodule RelaxedBooleanOrOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule StrictBooleanAndOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule SubtractionOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule TypeOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule UnaryNegativeOperator do
    defstruct value: nil
  end

  defmodule UnaryPositiveOperator do
    defstruct value: nil
  end

  # --- DATA TYPES ---

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

  defmodule NilType do
    defstruct []
  end

  defmodule StringType do
    defstruct value: nil, kind: :basic_data_type
  end

  defmodule StructType do
    defstruct module: nil, data: []
  end

  defmodule TupleType do
    defstruct data: []
  end

  # --- PSEUDO-VARIABLES ---

  defmodule EnvPseudoVariable do
    defstruct []
  end

  defmodule ModulePseudoVariable do
    defstruct []
  end

  # --- DEFINITIONS ---

  defmodule FunctionDefinition do
    defstruct name: nil,
              arity: nil,
              params: [],
              bindings: [],
              body: nil,
              visibility: nil
  end

  defmodule ModuleAttributeDefinition do
    defstruct name: nil, expression: nil
  end

  defmodule ModuleDefinition do
    defstruct module: nil, body: nil
  end

  # --- DIRECTIVES ---

  defmodule AliasDirective do
    defstruct alias_segs: nil, as: nil
  end

  # --- CONTROL FLOW ---

  defmodule Alias do
    defstruct segments: nil
  end

  defmodule AnonymousFunctionCall do
    defstruct name: nil, args: []
  end

  defmodule Block do
    defstruct expressions: []
  end

  defmodule Call do
    defstruct module: nil, function: nil, args: []
  end

  defmodule FunctionCall do
    defstruct module: nil, function: nil, args: [], erlang: false
  end

  defmodule Symbol do
    defstruct name: nil
  end

  # --- BINDINGS ---

  defmodule Binding do
    defstruct name: nil, access_path: []
  end

  defmodule MapAccess do
    defstruct key: nil
  end

  defmodule MatchAccess do
    defstruct []
  end

  # --- OTHER IR ---

  defmodule IgnoredExpression do
    defstruct type: nil
  end

  defmodule NotSupportedExpression do
    defstruct type: nil, ast: nil
  end

  # --- OVERHAUL ---

  # DATA TYPES

  defmodule ModuleType do
    defstruct module: nil, segments: nil
  end

  # OPERATORS

  defmodule EqualToOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  defmodule LessThanOperator do
    defstruct left: nil, right: nil, kind: :basic_binary_operator
  end

  # DEFINITIONS

  defmodule FunctionDefinitionVariants do
    defstruct name: nil, variants: []
  end

  # DIRECTIVES

  defmodule ImportDirective do
    defstruct alias_segs: nil, only: [], except: []
  end

  defmodule RequireDirective do
    defstruct alias_segs: nil
  end

  defmodule UseDirective do
    defstruct alias_segs: nil, opts: []
  end

  # CONTROL FLOW

  defmodule CaseExpression do
    defstruct condition: nil, clauses: []
  end

  defmodule IfExpression do
    defstruct condition: nil, do: nil, else: nil, ast: nil
  end

  # BINDINGS

  defmodule CaseConditionAccess do
    defstruct []
  end

  defmodule ListIndexAccess do
    defstruct index: nil, kind: :binding_index_access
  end

  defmodule ListTailAccess do
    defstruct []
  end

  defmodule ParamAccess do
    defstruct index: nil, kind: :binding_index_access
  end

  defmodule TupleAccess do
    defstruct index: nil, kind: :binding_index_access
  end

  # OTHER

  defmodule Variable do
    defstruct name: nil
  end
end
