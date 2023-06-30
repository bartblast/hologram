defmodule Hologram.Compiler.Analyzer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  defmodule Info do
    defstruct var_patterns: MapSet.new(), var_values: MapSet.new()

    @type t :: %__MODULE__{var_patterns: MapSet.t(atom), var_values: MapSet.t(atom)}
  end

  @doc """
  Analyzes an expression and returns analysis information.

  ## Examples

      iex> analyze(%IR.MatchOperator{left: %IR.Variable{name: :x}, right: %IR.Variable{name: :y}})
      %Info{var_patterns: #MapSet<[:x]>, var_values: #MapSet<[:y]>}

  """
  @spec analyze(any(), Context.t(), Info.t()) :: Info.t()
  def analyze(expr, context \\ %Context{}, info \\ %Info{})

  def analyze(%IR.Variable{name: name}, %{pattern?: true}, info) do
    %{info | var_patterns: MapSet.put(info.var_patterns, name)}
  end

  def analyze(%IR.Variable{name: name}, %{pattern?: false}, info) do
    %{info | var_values: MapSet.put(info.var_values, name)}
  end

  def analyze(%IR.MatchOperator{left: left, right: right}, context, info) do
    left_info = analyze(left, %{context | pattern?: true}, info)
    right_info = analyze(right, context, info)

    merge_info(left_info, right_info)
  end

  def analyze(ir, context, info) when is_list(ir) do
    Enum.reduce(ir, info, fn item, acc_info ->
      item_info = analyze(item, context, info)
      merge_info(acc_info, item_info)
    end)
  end

  def analyze(ir, context, info) when is_map(ir) do
    analyze(Map.to_list(ir), context, info)
  end

  def analyze(ir, context, info) when is_tuple(ir) do
    analyze(Tuple.to_list(ir), context, info)
  end

  def analyze(_ir, _context, info), do: info

  defp merge_info(info_1, info_2) do
    %Info{
      var_patterns: MapSet.union(info_1.var_patterns, info_2.var_patterns),
      var_values: MapSet.union(info_1.var_values, info_2.var_values)
    }
  end
end
