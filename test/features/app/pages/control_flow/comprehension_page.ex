defmodule HologramFeatureTests.ControlFlow.ComprehensionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.StructFixture1

  route "/control-flow/comprehension"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="basic_bitstring_generator"> Basic bitstring generator </button>
      <button $click="bitstring_generator_with_filter"> Bitstring generator with filter </button>
      <button $click="bitstring_generator_with_leftover_bits"> Bitstring generator with leftover bits </button>
      <button $click="bitstring_generator_with_multi_segment_pattern"> Bitstring generator with multi-segment pattern </button>
      <button $click="bitstring_generator_with_prefix_mismatch"> Bitstring generator with prefix mismatch </button>
      <button $click="dependent_generator"> Dependent generator </button>
      <button $click="guarding_filter"> Guarding filter </button>
      <button $click="reducer_with_all_rejecting_filter"> Reducer with all-rejecting filter </button>
      <button $click="reducer_with_bitstring_generator"> Reducer with bitstring generator </button>
      <button $click="reducer_with_clause_dispatch"> Reducer with clause dispatch </button>
      <button $click="reducer_with_empty_generator"> Reducer with empty generator </button>
      <button $click="reducer_with_guard_dispatch"> Reducer with guard dispatch </button>
      <button $click="reducer_with_multiple_generators"> Reducer with multiple generators </button>
      <button $click="reducer_with_outer_scope_access"> Reducer with outer scope access </button>
      <button $click="reducer_with_selective_filter"> Reducer with selective filter </button>
      <button $click="reducer_with_single_generator"> Reducer with single generator </button>
      <button $click="reducer_with_unmatched_accumulator"> Reducer with unmatched accumulator </button>
      <button $click="unique_with_map_and_subset"> Unique with a map and its subset </button>
    </p>
    <p>
      <button $click="generator_with_struct_pattern"> Generator with struct pattern </button>
      <button $click="struct_filtering_in_generator"> Struct filtering in generator </button>
      <button $click="reducer_with_struct_accumulator"> Reducer with struct accumulator </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:basic_bitstring_generator, _params, component) do
    result = for <<(x <- <<5, 6, 7>>)>>, do: x

    put_state(component, :result, result)
  end

  def action(:bitstring_generator_with_filter, _params, component) do
    result = for <<(x <- <<1, 2, 3>>)>>, rem(x, 2) == 1, do: x

    put_state(component, :result, result)
  end

  def action(:bitstring_generator_with_leftover_bits, _params, component) do
    result = for <<(x::8 <- <<1, 2, 3::4>>)>>, do: x

    put_state(component, :result, result)
  end

  def action(:bitstring_generator_with_multi_segment_pattern, _params, component) do
    result = for <<a::8, (b::8 <- <<1, 2, 3, 4>>)>>, do: {a, b}

    put_state(component, :result, result)
  end

  def action(:bitstring_generator_with_prefix_mismatch, _params, component) do
    result = for <<1::8, (x::8 <- <<1, 2, 3, 4>>)>>, do: x

    put_state(component, :result, result)
  end

  def action(:dependent_generator, _params, component) do
    result = for x <- [1, 2], y <- [x, x + 10], do: {x, y}

    put_state(component, :result, result)
  end

  def action(:guarding_filter, _params, component) do
    result = for x <- [[1, 2], :nope, [3]], is_list(x), y <- x, do: y

    put_state(component, :result, result)
  end

  def action(:reducer_with_all_rejecting_filter, _params, component) do
    result =
      for x <- [1, 2], x > 10, reduce: 200 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_bitstring_generator, _params, component) do
    result =
      for <<(x <- <<2, 3, 4>>)>>, reduce: 0 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_clause_dispatch, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        0 -> x
        acc -> acc * 10 + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_empty_generator, _params, component) do
    result =
      for x <- [], reduce: 100 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_guard_dispatch, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        acc when acc <= 1 -> acc + x
        acc -> acc + x * 10
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_multiple_generators, _params, component) do
    result =
      for x <- [1, 2], y <- [10, 20], reduce: 0 do
        acc -> acc + x * y
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_outer_scope_access, _params, component) do
    a = 1

    result =
      for x <- [10, 20], reduce: 0 do
        acc -> acc + x + a
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_selective_filter, _params, component) do
    result =
      for x <- [1, 2, 3, 4], rem(x, 2) == 0, reduce: 300 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_single_generator, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_unmatched_accumulator, _params, _component) do
    for x <- [1], reduce: 0 do
      :nomatch -> x
    end
  end

  def action(:unique_with_map_and_subset, _params, component) do
    result = for x <- [%{a: 1, b: 2}, %{a: 1}], uniq: true, do: x

    put_state(component, :result, result)
  end

  def action(:generator_with_struct_pattern, _params, component) do
    result =
      for %StructFixture1{value: v} <- [
            %StructFixture1{name: "a", value: 1},
            %StructFixture1{name: "b", value: 2}
          ],
          do: v * 10

    put_state(component, :result, result)
  end

  # A generator skips the elements its pattern doesn't match,
  # rather than failing the whole comprehension.
  def action(:struct_filtering_in_generator, _params, component) do
    result =
      for %StructFixture1{value: v} <- [
            %StructFixture1{name: "a", value: 1},
            %{name: "plain", value: 2},
            %StructFixture1{name: "c", value: 3}
          ],
          do: v

    put_state(component, :result, result)
  end

  # The struct pattern stands alone in the clause head - binding it with
  # `= acc` would route the pattern through the match operator instead.
  def action(:reducer_with_struct_accumulator, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: %StructFixture1{name: "acc", value: 0} do
        %StructFixture1{name: n, value: v} -> %StructFixture1{name: n, value: v + x}
      end

    put_state(component, :result, result)
  end
end
