defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  @type t ::
          IR.AnonymousFunctionCall.t()
          | IR.AnonymousFunctionClause.t()
          | IR.AnonymousFunctionType.t()
          | IR.AtomType.t()
          | IR.BitstringSegment.t()
          | IR.BitstringType.t()
          | IR.Block.t()
          | IR.CaseClause.t()
          | IR.CaseExpression.t()
          | IR.Comprehension.t()
          | IR.ComprehensionFilter.t()
          | IR.ComprehensionGenerator.t()
          | IR.CondClause.t()
          | IR.CondExpression.t()
          | IR.ConsOperator.t()
          | IR.DotOperator.t()
          | IR.FloatType.t()
          | IR.FunctionDefinition.t()
          | IR.IgnoredExpression.t()
          | IR.IntegerType.t()
          | IR.ListType.t()
          | IR.LocalFunctionCall.t()
          | IR.MapType.t()
          | IR.MatchOperator.t()
          | IR.MatchPlaceholder.t()
          | IR.ModuleAttributeOperator.t()
          | IR.ModuleDefinition.t()
          | IR.PinOperator.t()
          | IR.RemoteFunctionCall.t()
          | IR.StringType.t()
          | IR.TupleType.t()
          | IR.Variable.t()

  defmodule AnonymousFunctionCall do
    defstruct [:function, :args]

    @type t :: %__MODULE__{function: IR.t(), args: list(IR.t())}
  end

  defmodule AnonymousFunctionClause do
    defstruct [:params, :guard, :body]

    @type t :: %__MODULE__{params: list(IR.t()), guard: IR.t() | nil, body: IR.Block.t()}
  end

  defmodule AnonymousFunctionType do
    defstruct [:arity, :clauses]

    @type t :: %__MODULE__{arity: integer, clauses: list(IR.AnonymousFunctionClause.t())}
  end

  defmodule AtomType do
    defstruct [:value]

    @type t :: %__MODULE__{value: atom}
  end

  defmodule BitstringSegment do
    defstruct [:value, :modifiers]

    @type(
      modifier :: {:endianness, :big | :little | :native} | {:signedness, :signed | :unsigned},
      {:size, IR.t()},
      {:type, :binary | :bitstring | :float | :integer | :utf8 | :utf16 | :utf32},
      {:unit, integer}
    )

    @type t :: %__MODULE__{value: IR.t(), modifiers: list(modifier)}
  end

  defmodule BitstringType do
    defstruct [:segments]

    @type t :: %__MODULE__{segments: list(IR.BitstringSegment.t())}
  end

  defmodule Block do
    defstruct [:expressions]

    @type t :: %__MODULE__{expressions: list(IR.t())}
  end

  defmodule CaseClause do
    defstruct [:head, :guard, :body]

    @type t :: %__MODULE__{head: IR.t(), guard: IR.t() | nil, body: IR.Block.t()}
  end

  defmodule CaseExpression do
    defstruct [:condition, :clauses]

    @type t :: %__MODULE__{condition: IR.t(), clauses: list(IR.CaseClause.t())}
  end

  defmodule Comprehension do
    defstruct [:generators, :filters, :collectable, :unique, :mapper]

    @type t :: %__MODULE__{
            generators: list(IR.ComprehensionGenerator.t()),
            filters: list(IR.ComprehensionFilter.t()),
            collectable: IR.t(),
            unique: %IR.AtomType{value: boolean},
            mapper: IR.t()
          }
  end

  defmodule ComprehensionFilter do
    defstruct [:expression]

    @type t :: %__MODULE__{expression: IR.t()}
  end

  defmodule ComprehensionGenerator do
    defstruct [:enumerable, :match, :guard]

    @type t :: %__MODULE__{enumerable: IR.t(), match: IR.t(), guard: IR.t() | nil}
  end

  defmodule CondClause do
    defstruct [:condition, :body]

    @type t :: %__MODULE__{condition: IR.t(), body: IR.Block.t()}
  end

  defmodule CondExpression do
    defstruct [:clauses]

    @type t :: %__MODULE__{clauses: list(IR.CondClause.t())}
  end

  defmodule ConsOperator do
    defstruct [:head, :tail]

    @type t :: %__MODULE__{head: IR.t(), tail: IR.t()}
  end

  defmodule DotOperator do
    defstruct [:left, :right]

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule FloatType do
    defstruct [:value]

    @type t :: %__MODULE__{value: float}
  end

  defmodule FunctionDefinition do
    defstruct [:name, :arity, :params, :body, :visibility]

    @type t :: %__MODULE__{
            name: atom,
            arity: integer,
            params: list(IR.t()),
            body: IR.Block.t(),
            visibility: :public | :private
          }
  end

  defmodule IgnoredExpression do
    defstruct [:type]

    @type t :: %__MODULE__{type: :public_macro_definition | :private_macro_definition}
  end

  defmodule IntegerType do
    defstruct [:value]

    @type t :: %__MODULE__{value: integer}
  end

  defmodule ListType do
    defstruct [:data]

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule LocalFunctionCall do
    defstruct [:function, :args]

    @type t :: %__MODULE__{function: atom, args: list(IR.t())}
  end

  defmodule MapType do
    defstruct [:data]

    @type t :: %__MODULE__{data: list({IR.t(), IR.t()})}
  end

  defmodule MatchOperator do
    defstruct [:left, :right]

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule MatchPlaceholder do
    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule ModuleAttributeOperator do
    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  defmodule ModuleDefinition do
    defstruct [:module, :body]

    @type t :: %__MODULE__{module: IR.AtomType.t(), body: IR.Block.t()}
  end

  defmodule PinOperator do
    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  defmodule RemoteFunctionCall do
    defstruct [:module, :function, :args]

    @type t :: %__MODULE__{module: IR.t(), function: IR.t(), args: list(IR.t())}
  end

  defmodule StringType do
    defstruct [:value]

    @type t :: %__MODULE__{value: String.t()}
  end

  defmodule TupleType do
    defstruct [:data]

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule Variable do
    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  @doc """
  Given Elixir source code returns its Hologram IR.

  ## Examples

      iex> for_code("my_fun(1, 2)")
      %IR.LocalFunctionCall{function: :my_fun, args: [%IR.IntegerType{value: 1}, %IR.IntegerType{value: 2}]}
  """
  @spec for_code(binary, Context.t()) :: IR.t()
  def for_code(code, %Context{} = context) do
    code
    |> AST.for_code()
    |> Transformer.transform(context)
  end
end
