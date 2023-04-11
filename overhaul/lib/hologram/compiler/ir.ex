defmodule Hologram.Compiler.IR do
  # --- DATA TYPES ---

  defmodule AnonymousFunctionType do
    defstruct arity: nil, params: [], bindings: [], body: nil
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

  defmodule ModuleDefinition do
    defstruct module: nil, body: nil
  end

  # --- CONTROL FLOW ---

  defmodule Block do
    defstruct expressions: []
  end

  defmodule CaseExpression do
    defstruct condition: nil, clauses: []
  end

  defmodule IfExpression do
    defstruct condition: nil, do: nil, else: nil
  end

  # --- BINDINGS ---

  defmodule Binding do
    defstruct name: nil, access_path: []
  end

  defmodule CaseConditionAccess do
    defstruct []
  end

  defmodule ListIndexAccess do
    defstruct index: nil
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

  # --- OVERHAUL ---

  # DEFINITIONS

  defmodule FunctionDefinitionVariants do
    defstruct name: nil, variants: []
  end

  # BINDINGS

  defmodule ListTailAccess do
    defstruct []
  end

  defmodule ParamAccess do
    defstruct index: nil
  end

  defmodule TupleAccess do
    defstruct index: nil
  end
end
