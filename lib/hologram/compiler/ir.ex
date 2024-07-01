defmodule Hologram.Compiler.IR do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Transformer

  @type t ::
          IR.AnonymousFunctionCall.t()
          | IR.AnonymousFunctionType.t()
          | IR.AtomType.t()
          | IR.BitstringSegment.t()
          | IR.BitstringType.t()
          | IR.Block.t()
          | IR.Case.t()
          | IR.Clause.t()
          | IR.Comprehension.t()
          | IR.ComprehensionFilter.t()
          | IR.Cond.t()
          | IR.CondClause.t()
          | IR.ConsOperator.t()
          | IR.DotOperator.t()
          | IR.FloatType.t()
          | IR.FunctionClause.t()
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
          | IR.PIDType.t()
          | IR.PinOperator.t()
          | IR.PortType.t()
          | IR.ReferenceType.t()
          | IR.RemoteFunctionCall.t()
          | IR.StringType.t()
          | IR.Try.t()
          | IR.TryCatchClause.t()
          | IR.TryRescueClause.t()
          | IR.TupleType.t()
          | IR.Variable.t()
          | IR.With.t()

  defmodule AnonymousFunctionCall do
    defstruct [:function, :args]

    @type t :: %__MODULE__{function: IR.t(), args: list(IR.t())}
  end

  defmodule AnonymousFunctionType do
    defstruct [:arity, :captured_function, :captured_module, :clauses]

    @type t :: %__MODULE__{
            arity: integer,
            captured_function: atom | nil,
            captured_module: module | nil,
            clauses: list(IR.FunctionClause.t())
          }
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

  defmodule Case do
    defstruct [:condition, :clauses]

    @type t :: %__MODULE__{condition: IR.t(), clauses: list(IR.Clause.t())}
  end

  defmodule Clause do
    defstruct [:match, :guards, :body]

    @type t :: %__MODULE__{match: IR.t(), guards: list(IR.t()), body: IR.Block.t()}
  end

  defmodule Comprehension do
    defstruct [:generators, :filters, :collectable, :unique, :mapper, :reducer]

    @type t :: %__MODULE__{
            generators: list(IR.Clause.t()),
            filters: list(IR.ComprehensionFilter.t()),
            collectable: IR.t(),
            unique: %IR.AtomType{value: boolean},
            mapper: IR.Block.t() | nil,
            reducer:
              %{
                initial_value: IR.t(),
                clauses: list(IR.Clause.t())
              }
              | nil
          }
  end

  defmodule ComprehensionFilter do
    defstruct [:expression]

    @type t :: %__MODULE__{expression: IR.t()}
  end

  defmodule Cond do
    defstruct [:clauses]

    @type t :: %__MODULE__{clauses: list(IR.CondClause.t())}
  end

  defmodule CondClause do
    defstruct [:condition, :body]

    @type t :: %__MODULE__{condition: IR.t(), body: IR.Block.t()}
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

  defmodule FunctionClause do
    defstruct [:params, :guards, :body]

    @type t :: %__MODULE__{params: list(IR.t()), guards: list(IR.t()), body: IR.Block.t()}
  end

  defmodule FunctionDefinition do
    defstruct [:name, :arity, :visibility, :clause]

    @type t :: %__MODULE__{
            name: atom,
            arity: integer,
            visibility: :public | :private,
            clause: IR.FunctionClause.t()
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

  defmodule PIDType do
    defstruct [:value]

    @type t :: %__MODULE__{value: pid}
  end

  defmodule PinOperator do
    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  defmodule PortType do
    defstruct [:value]

    @type t :: %__MODULE__{value: port}
  end

  defmodule ReferenceType do
    defstruct [:value]

    @type t :: %__MODULE__{value: reference}
  end

  defmodule RemoteFunctionCall do
    defstruct [:module, :function, :args]

    @type t :: %__MODULE__{module: IR.t(), function: IR.t(), args: list(IR.t())}
  end

  defmodule StringType do
    defstruct [:value]

    @type t :: %__MODULE__{value: String.t()}
  end

  defmodule Try do
    defstruct [:body, :rescue_clauses, :catch_clauses, :else_clauses, :after_block]

    @type t :: %__MODULE__{
            body: IR.Block.t(),
            rescue_clauses: list(IR.TryRescueClause.t()),
            catch_clauses: list(IR.TryCatchClause.t()),
            else_clauses: list(IR.Clause.t()),
            after_block: IR.Block.t()
          }
  end

  defmodule TryCatchClause do
    defstruct [:kind, :value, :guards, :body]

    @type t :: %__MODULE__{
            kind: IR.t() | nil,
            value: IR.t(),
            guards: list(IR.t()),
            body: IR.Block.t()
          }
  end

  defmodule TryRescueClause do
    defstruct [:variable, :modules, :body]

    @type t :: %__MODULE__{variable: atom, modules: list(module), body: IR.Block.t()}
  end

  defmodule TupleType do
    defstruct [:data]

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule Variable do
    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  # TODO: finish implementing
  defmodule With do
    defstruct []

    @type t :: %__MODULE__{}
  end

  @doc """
  Returns Hologram IR for the given Elixir source code.

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

  @doc """
  Returns Hologram IR for the given module.
  Specifying the module's BEAM path makes the call faster.

  ## Examples

      iex> for_module(MyModule)
      %IR.ModuleDefinition{module: MyModule, body: %IR.Block{expressions: [...]}}
  """
  @spec for_module(module, charlist | nil) :: IR.t()
  def for_module(module, beam_path \\ nil) do
    input = beam_path || :code.which(module)

    input
    |> BeamFile.elixir_quoted!()
    |> Normalizer.normalize()
    |> Transformer.transform(%Context{module: module})
  end

  @doc """
  Returns Hologram IR for the given Elixir term.
  If the term can be represented in IR then its value is returned in the shape of {:ok, ir}.
  If the term can't be represented in IR then an error message is returned in the shape of {:error, message}.

  ## Examples

      iex> my_var = 123
      iex> for_term(my_var)
      {:ok, %IR.IntegerType{value: 123}}
  """
  @spec for_term(any) :: {:ok, IR.t()} | {:error, String.t()}
  def for_term(term) do
    {:ok, for_term!(term)}
  rescue
    e in ArgumentError ->
      {:error, e.message}
  end

  @doc """
  Returns Hologram IR for the given Elixir term, erroring out if the term can't be represented in IR.

  ## Examples

      iex> my_var = 123
      iex> for_term!(my_var)
      %IR.IntegerType{value: 123}
  """
  @spec for_term!(any) :: IR.t()
  def for_term!(term)

  def for_term!(term) when is_function(term) do
    if Function.info(term)[:type] == :external do
      term
      |> Macro.escape()
      |> Transformer.transform(%Context{})
    else
      raise ArgumentError,
        message: "term contains an anonymous function that is not a named function capture"
    end
  end

  def for_term!(term) when is_bitstring(term) do
    term
    |> Macro.escape()
    |> Transformer.transform(%Context{})
  end

  def for_term!(term) when is_list(term) do
    data = Enum.map(term, &for_term!/1)
    %IR.ListType{data: data}
  end

  def for_term!(term) when is_map(term) do
    data =
      term
      |> Map.to_list()
      |> Enum.map(fn {key, value} -> {for_term!(key), for_term!(value)} end)

    %IR.MapType{data: data}
  end

  def for_term!(term) when is_tuple(term) do
    data =
      term
      |> Tuple.to_list()
      |> Enum.map(&for_term!/1)

    %IR.TupleType{data: data}
  end

  # atom, float, integer, pid, port, reference
  def for_term!(term) do
    Transformer.transform(term, %Context{})
  end
end
