defmodule HologramFeatureTests.LongGuardsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  @dialyzer :no_match

  # A guard over a list this long is a chain of as many comparisons, one inside the other. A
  # browser has to be able to parse the page's script whatever the length of the chain.
  @value_count 600

  @atoms for i <- 1..@value_count, do: :"zone_#{i}"

  @binaries for i <- 1..@value_count, do: "Zone/#{i}"

  @integers Enum.to_list(1..@value_count)

  # The last value of each list, the one a chain of comparisons reaches last
  @last_atom List.last(@atoms)

  @last_binary List.last(@binaries)

  @last_integer List.last(@integers)

  # Equal to the last integer for ==, and to no integer for ===
  @last_integer_as_float @last_integer * 1.0

  route "/long-guards"

  layout HologramFeatureTests.Components.DefaultLayout

  # A chain as long as the lists above that no value can be looked up for: == holds for a float
  # equal to one of the integers, so every comparison has to be made.
  defmacrop loosely_equals_any_integer(var) do
    Enum.reduce(2..@value_count, quote(do: unquote(var) == 1), fn integer, acc ->
      quote(do: unquote(acc) or unquote(var) == unquote(integer))
    end)
  end

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="atom_list"> Atom list </button>
      <button $click="binary_list"> Binary list </button>
      <button $click="case_clause"> Case clause </button>
      <button $click="fall_through"> Fall through </button>
      <button $click="integer_list"> Integer list </button>
      <button $click="loose_chain"> Loose chain </button>
      <button $click="mixed_list"> Mixed list </button>
      <button $click="no_matching_clause"> No matching clause </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:atom_list, _params, component) do
    result =
      @last_atom
      |> wrap_term()
      |> in_atoms()

    put_state(component, :result, result)
  end

  def action(:binary_list, _params, component) do
    result =
      @last_binary
      |> wrap_term()
      |> in_binaries()

    put_state(component, :result, result)
  end

  def action(:case_clause, _params, component) do
    result =
      case wrap_term("Zone/300") do
        x when x in @binaries -> :case_match
        _x -> :case_no_match
      end

    put_state(component, :result, result)
  end

  def action(:fall_through, _params, component) do
    result =
      "Nowhere"
      |> wrap_term()
      |> in_binaries()

    put_state(component, :result, result)
  end

  def action(:integer_list, _params, component) do
    result =
      @last_integer
      |> wrap_term()
      |> in_integers()

    put_state(component, :result, result)
  end

  def action(:loose_chain, _params, component) do
    result =
      @last_integer_as_float
      |> wrap_term()
      |> loosely_in_integers()

    put_state(component, :result, result)
  end

  def action(:mixed_list, _params, component) do
    result =
      {:gamma, 6}
      |> wrap_term()
      |> in_mixed()

    put_state(component, :result, result)
  end

  def action(:no_matching_clause, _params, _component) do
    123
    |> wrap_term()
    |> only_binaries()
  end

  def in_atoms(x) when x in @atoms, do: :atom_match
  def in_atoms(_x), do: :atom_no_match

  def in_binaries(x) when x in @binaries, do: :binary_match
  def in_binaries(_x), do: :binary_no_match

  def in_integers(x) when x in @integers, do: :integer_match
  def in_integers(_x), do: :integer_no_match

  def in_mixed(x) when x in [:alpha, "beta", 3, 4.5, {:gamma, 6}], do: :mixed_match
  def in_mixed(_x), do: :mixed_no_match

  def loosely_in_integers(x) when loosely_equals_any_integer(x), do: :loose_match
  def loosely_in_integers(_x), do: :loose_no_match

  def only_binaries(x) when x in @binaries, do: :only_match
end
