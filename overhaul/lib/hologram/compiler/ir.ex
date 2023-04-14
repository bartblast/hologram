defmodule Hologram.Compiler.IR do
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
