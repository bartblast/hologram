defmodule Hologram.Compiler.IR do
  @moduledoc false

  alias Hologram.Commons.AtomUtils
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.ClauseBlame
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Transformer

  # `%Context{}` literals carry the struct's `MapSet.new()` default, which newer Dialyzer
  # reads as a concrete MapSet and won't unify with the opaque `MapSet.t()` in the specs of
  # the functions these contexts are passed to.
  @dialyzer {:no_opaque, [build_function_capture_ir: 3, for_module: 2, for_term!: 1]}

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
          | IR.ComprehensionBitstringGenerator.t()
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
          | IR.Stacktrace.t()
          | IR.StringType.t()
          | IR.Try.t()
          | IR.TryCatchClause.t()
          | IR.TryRescueClause.t()
          | IR.TupleType.t()
          | IR.Variable.t()
          | IR.With.t()
          | IR.WithBareClause.t()
          | IR.WithMatchClause.t()

  defmodule AnonymousFunctionCall do
    @moduledoc false

    # line is the call's line in the module's source file, or nil when the AST
    # metadata carries none. A stacktrace frame reports the line of the call
    # being made, which is how the BEAM records it.
    defstruct [:function, :args, :line]

    @type t :: %__MODULE__{function: IR.t(), args: list(IR.t()), line: integer | nil}
  end

  defmodule AnonymousFunctionType do
    @moduledoc false

    defstruct [:arity, :captured_function, :captured_module, :clauses]

    @type t :: %__MODULE__{
            arity: integer,
            captured_function: atom | nil,
            captured_module: module | nil,
            clauses: list(IR.FunctionClause.t())
          }
  end

  defmodule AtomType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: atom}
  end

  defmodule BitstringSegment do
    @moduledoc false

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
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:segments, :line]

    @type t :: %__MODULE__{segments: list(IR.BitstringSegment.t()), line: integer | nil}
  end

  defmodule Block do
    @moduledoc false

    defstruct [:expressions]

    @type t :: %__MODULE__{expressions: list(IR.t())}
  end

  defmodule Case do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:condition, :clauses, :line]

    @type t :: %__MODULE__{
            condition: IR.t(),
            clauses: list(IR.Clause.t()),
            line: integer | nil
          }
  end

  defmodule Clause do
    @moduledoc false

    defstruct [:match, :guards, :body]

    @type t :: %__MODULE__{match: IR.t(), guards: list(IR.t()), body: IR.Block.t()}
  end

  defmodule Comprehension do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:qualifiers, :collectable, :unique, :mapper, :reducer, :line]

    @type t :: %__MODULE__{
            qualifiers:
              list(
                IR.Clause.t()
                | IR.ComprehensionBitstringGenerator.t()
                | IR.ComprehensionFilter.t()
              ),
            collectable: IR.t(),
            unique: %IR.AtomType{value: boolean},
            mapper: IR.Block.t() | nil,
            reducer:
              %{
                initial_value: IR.t(),
                clauses: list(IR.Clause.t())
              }
              | nil,
            line: integer | nil
          }
  end

  defmodule ComprehensionBitstringGenerator do
    @moduledoc false

    defstruct [:match, :body]

    @type t :: %__MODULE__{match: IR.BitstringType.t(), body: IR.t()}
  end

  defmodule ComprehensionFilter do
    @moduledoc false

    defstruct [:expression]

    @type t :: %__MODULE__{expression: IR.t()}
  end

  defmodule Cond do
    @moduledoc false

    # line is the last clause's line, which is where the BEAM reports a cond
    # that matched none of them - cond expands into nested cases, and the raise
    # ends up in the innermost one. See IR.AnonymousFunctionCall about line.
    defstruct [:clauses, :line]

    @type t :: %__MODULE__{clauses: list(IR.CondClause.t()), line: integer | nil}
  end

  defmodule CondClause do
    @moduledoc false

    defstruct [:condition, :body]

    @type t :: %__MODULE__{condition: IR.t(), body: IR.Block.t()}
  end

  defmodule ConsOperator do
    @moduledoc false

    defstruct [:head, :tail]

    @type t :: %__MODULE__{head: IR.t(), tail: IR.t()}
  end

  defmodule DotOperator do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:left, :right, :line]

    @type t :: %__MODULE__{left: IR.t(), right: IR.t(), line: integer | nil}
  end

  defmodule FloatType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: float}
  end

  defmodule FunctionClause do
    @moduledoc false

    # line is the clause head's line in the module's source file, or nil when
    # the AST metadata carries none.
    # blame is the clause head rendered for attempted-clause reporting, or nil
    # for an anonymous function clause, which the server doesn't report either.
    defstruct [:params, :guards, :body, :line, :blame]

    @type t :: %__MODULE__{
            params: list(IR.t()),
            guards: list(IR.t()),
            body: IR.Block.t(),
            line: integer | nil,
            blame: %{params: list(String.t()), guards: list(ClauseBlame.guard())} | nil
          }
  end

  defmodule FunctionDefinition do
    @moduledoc false

    defstruct [:name, :arity, :visibility, :clause]

    @type t :: %__MODULE__{
            name: atom,
            arity: integer,
            visibility: :public | :private,
            clause: IR.FunctionClause.t()
          }
  end

  defmodule IgnoredExpression do
    @moduledoc false

    defstruct [:type]

    @type t :: %__MODULE__{type: :public_macro_definition | :private_macro_definition}
  end

  defmodule IntegerType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: integer}
  end

  defmodule ListType do
    @moduledoc false

    defstruct [:data]

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule LocalFunctionCall do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:function, :args, :line]

    @type t :: %__MODULE__{function: atom, args: list(IR.t()), line: integer | nil}
  end

  defmodule MapType do
    @moduledoc false

    defstruct [:data]

    @type t :: %__MODULE__{data: list({IR.t(), IR.t()})}
  end

  defmodule MatchOperator do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:left, :right, :line]

    @type t :: %__MODULE__{left: IR.t(), right: IR.t(), line: integer | nil}
  end

  defmodule MatchPlaceholder do
    @moduledoc false

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule ModuleAttributeOperator do
    @moduledoc false

    defstruct [:name]

    @type t :: %__MODULE__{name: atom}
  end

  defmodule ModuleDefinition do
    @moduledoc false

    defstruct [:module, :body]

    @type t :: %__MODULE__{module: IR.AtomType.t(), body: IR.Block.t()}
  end

  defmodule PIDType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: pid}
  end

  defmodule PinOperator do
    @moduledoc false

    defstruct [:variable]

    @type t :: %__MODULE__{variable: IR.Variable.t()}
  end

  defmodule PortType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: port}
  end

  defmodule ReferenceType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: reference}
  end

  defmodule RemoteFunctionCall do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:module, :function, :args, :line]

    @type t :: %__MODULE__{
            module: IR.t(),
            function: atom,
            args: list(IR.t()),
            line: integer | nil
          }
  end

  defmodule Stacktrace do
    @moduledoc false

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule StringType do
    @moduledoc false

    defstruct [:value]

    @type t :: %__MODULE__{value: String.t()}
  end

  defmodule Try do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:body, :rescue_clauses, :catch_clauses, :else_clauses, :after_block, :line]

    @type t :: %__MODULE__{
            body: IR.Block.t(),
            rescue_clauses: list(IR.TryRescueClause.t()),
            catch_clauses: list(IR.TryCatchClause.t()),
            else_clauses: list(IR.Clause.t()),
            after_block: IR.Block.t(),
            line: integer | nil
          }
  end

  defmodule TryCatchClause do
    @moduledoc false

    defstruct [:kind, :value, :guards, :body]

    @type t :: %__MODULE__{
            kind: IR.t() | nil,
            value: IR.t(),
            guards: list(IR.t()),
            body: IR.Block.t()
          }
  end

  defmodule TryRescueClause do
    @moduledoc false

    defstruct [:variable, :modules, :body]

    @type t :: %__MODULE__{variable: atom, modules: list(module), body: IR.Block.t()}
  end

  defmodule TupleType do
    @moduledoc false

    defstruct [:data]

    @type t :: %__MODULE__{data: list(IR.t())}
  end

  defmodule Variable do
    @moduledoc false

    defstruct [:name, :version]

    @type t :: %__MODULE__{name: atom, version: integer | nil}
  end

  defmodule With do
    @moduledoc false

    # See IR.AnonymousFunctionCall about line.
    defstruct [:clauses, :body, :else_clauses, :line]

    @type t :: %__MODULE__{
            clauses: list(IR.WithBareClause.t() | IR.WithMatchClause.t()),
            body: IR.Block.t(),
            else_clauses: list(IR.Clause.t()),
            line: integer | nil
          }
  end

  defmodule WithBareClause do
    @moduledoc false

    defstruct [:expression]

    @type t :: %__MODULE__{expression: IR.t()}
  end

  defmodule WithMatchClause do
    @moduledoc false

    defstruct [:match, :guards, :expression]

    @type t :: %__MODULE__{match: IR.t(), guards: list(IR.t()), expression: IR.t()}
  end

  @doc """
  Aggregates function clauses from a module definition, sorted by function name and arity.

  ## Returns

  A list, where each item is in the format:
  {{function_name, arity}, {visibility, [clause_1, clause_2, ...]}}

  ## Example

      iex> module_def = %ModuleDefinition{...}
      iex> aggregate_module_funs(module_def)
      [
        {{:my_function_1, 3}, {:public, [%IR.FunctionClause{...}, %IR.FunctionClause{...}]}},
        {{:my_function_2, 1}, {:private, [%IR.FunctionClause{...}]}}
      ]
  """
  @spec aggregate_module_funs(ModuleDefinition.t()) ::
          list({{atom, non_neg_integer}, {:public | :private, list(FunctionClause.t())}})
  def aggregate_module_funs(module_def) do
    module_def.body.expressions
    |> Enum.reduce(%{}, fn
      %IR.FunctionDefinition{name: name, arity: arity, visibility: visibility, clause: clause},
      acc ->
        key = {name, arity}

        if acc[key] do
          {visibility, clauses} = acc[key]
          %{acc | key => {visibility, [clause | clauses]}}
        else
          Map.put(acc, key, {visibility, [clause]})
        end

      _expr, acc ->
        acc
    end)
    |> Enum.map(fn {key, {visibility, clauses}} -> {key, {visibility, Enum.reverse(clauses)}} end)
    # The order a bundle lists its functions in is chosen here rather than inherited from the
    # accumulator's layout, which is sorted only while a module holds 32 or fewer functions.
    # The same reachable set then always renders the same bytes.
    |> Enum.sort_by(fn {key, _fun} -> key end)
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
  Returns Hologram IR of the given module.
  Specifying the module's BEAM path or BEAM binary makes the call faster.

  ## Examples

      iex> for_module(MyModule)
      %IR.ModuleDefinition{module: MyModule, body: %IR.Block{expressions: [...]}}
  """
  # TODO: Narrow the spec back to charlist, and rename the param back to
  # beam_path, when Hologram.Compiler.resolve_beam_source/2 goes (see the
  # removal note there) - nothing passes a BEAM binary here after that.
  @spec for_module(module, charlist | binary | nil) :: IR.t()
  def for_module(module, beam_source \\ nil) do
    module
    |> AST.for_module(beam_source)
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

  # credo:disable-for-lines:34 Credo.Check.Refactor.CyclomaticComplexity
  def for_term!(term) when is_function(term) do
    function_info = Function.info(term)

    cond do
      function_info[:type] == :external ->
        build_function_capture_ir(term, function_info[:module], function_info[:name])

      SystemUtils.otp_version() >= 25 && function_info[:type] == :local &&
          !AtomUtils.starts_with?(function_info[:name], "-") ->
        function_info[:module]
        |> Function.capture(function_info[:name], function_info[:arity])
        |> build_function_capture_ir(function_info[:module], function_info[:name])

      SystemUtils.otp_version() < 25 && function_info[:type] == :local &&
          AtomUtils.starts_with?(function_info[:name], "-fun.") ->
        regex = ~r'^\-fun\.(.+)/[0-9]+\-$'
        [_full_match, function_str] = Regex.run(regex, to_string(function_info[:name]))
        function = String.to_existing_atom(function_str)

        function_info[:module]
        |> Function.capture(function, function_info[:arity])
        |> build_function_capture_ir(function_info[:module], function)

      true ->
        message =
          if SystemUtils.otp_version() >= 23 do
            "term contains a function that is not a named function capture"
          else
            "term contains a function that is not a remote function capture"
          end

        raise ArgumentError, message: message
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

  def for_term!(%Regex{} = term) do
    # A compiled pattern exists only inside the runtime that compiled it, so
    # the client rebuilds it through the same pathway as regex literals: an
    # exported pattern imported with :re.import/1, which registers the
    # compiled pattern in the client runtime.
    {:ok, exported} = :re.compile(term.source, [:export | term.opts])

    import_call_ir = %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: :re},
      function: :import,
      args: [for_term!(exported)]
    }

    data =
      term
      |> Map.to_list()
      |> Enum.map(fn
        {:re_pattern, _compiled_pattern} ->
          {%IR.AtomType{value: :re_pattern}, import_call_ir}

        {key, value} ->
          {for_term!(key), for_term!(value)}
      end)

    %IR.MapType{data: data}
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

  @doc """
  Walks the IR tree checking whether any function call matches the given set of MFAs.
  Stops at nested `AnonymousFunctionType` nodes (they are independent scopes).
  """
  @spec has_call_to?(any, module, MapSet.t()) :: boolean
  def has_call_to?(term, module, mfas)

  def has_call_to?(%IR.AnonymousFunctionType{}, _module, _mfas), do: false

  def has_call_to?(%IR.LocalFunctionCall{function: function, args: args}, module, mfas) do
    MapSet.member?(mfas, {module, function, length(args)}) || has_call_to?(args, module, mfas)
  end

  def has_call_to?(
        %IR.RemoteFunctionCall{
          module: %IR.AtomType{value: call_module},
          function: function,
          args: args
        },
        module,
        mfas
      ) do
    MapSet.member?(mfas, {call_module, function, length(args)}) ||
      has_call_to?(args, module, mfas)
  end

  def has_call_to?(term, module, mfas) when is_list(term) do
    Enum.any?(term, &has_call_to?(&1, module, mfas))
  end

  def has_call_to?(term, module, mfas) when is_map(term) do
    term
    |> Map.values()
    |> has_call_to?(module, mfas)
  end

  def has_call_to?(term, module, mfas) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> has_call_to?(module, mfas)
  end

  def has_call_to?(_term, _module, _mfas), do: false

  defp build_function_capture_ir(function_capture, module, function) do
    function_capture
    |> Macro.escape()
    |> Transformer.transform(%Context{})
    |> Map.put(:captured_module, module)
    |> Map.put(:captured_function, function)
  end
end
