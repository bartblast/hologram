defmodule Hologram.Query.ShapeTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Shape

  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26
  alias Hologram.Test.Fixtures.Query.Shape.Module1
  alias Hologram.Test.Fixtures.Query.Shape.Module2
  alias Hologram.Test.Fixtures.Query.Shape.Module3
  alias Hologram.Test.Fixtures.Query.Shape.Module4
  alias Hologram.Test.Fixtures.Query.Shape.Module5

  defp recorded_shapes(module) do
    attributes = module.__info__(:attributes)

    attributes
    |> Keyword.get_values(attribute())
    |> Enum.concat()
    |> Enum.sort()
  end

  describe "record/3" do
    test "records the chain each stage of a pipe ends, each once" do
      filter_stage = {:filter, [[a: {:==, %Placeholder{name: :a}}]]}

      assert recorded_shapes(Module1) ==
               Enum.sort([
                 {Entity2, [filter_stage]},
                 {Entity2, [filter_stage, sort: [:b]]},
                 {Entity2, [filter_stage, sort: [:b], take: [5]]}
               ])
    end

    test "records nested stage calls and the cardinality stages" do
      assert recorded_shapes(Module2) ==
               Enum.sort([
                 {Entity2, [filter: [[a: {:==, true}]]]},
                 {Entity2, [filter: [[a: {:==, true}]], count: []]},
                 {Entity2, [filter: [[b: {:==, %Placeholder{name: :b}}]]]},
                 {Entity2, [filter: [[b: {:==, %Placeholder{name: :b}}]], one: []]}
               ])
    end

    test "records nothing for a query held in a variable, a pinned predicate list or a pinned include spec on the type alone" do
      assert recorded_shapes(Module3) == []
    end

    test "records chains starting at __MODULE__ or a module attribute, pins the stages take, and leaves what an include pins out of its chain" do
      bounds = [{:>=, %Placeholder{name: :lo}}, {:<=, %Placeholder{name: :hi}}]
      filter_a = {:filter, [[a: {:==, %Placeholder{name: :a}}]]}
      opts = %Placeholder{name: :opts}

      assert recorded_shapes(Module5) ==
               Enum.sort([
                 {Entity2, [filter: [[a: {:==, true}]]]},
                 {Module5, [take: [1]]},
                 {Entity2, [filter: [[b: bounds]]]},
                 {Entity2, [filter: [[b: bounds]], take: [%Placeholder{name: :n}]]},
                 {Entity2, [filter: [[b: bounds]], take: [3]]},
                 {Entity2, [filter_a]},
                 {Entity2, [filter_a, take: [5]]},
                 {Entity26, [include: [[:topic]]]},
                 {Entity2, [sort: [:b]]},
                 {Entity2, [sort: [:b], paginate: [[page: opts, size: opts]]]},
                 {Entity26,
                  [filter: [[any: {[:messages], [body: {:==, %Placeholder{name: :body}}]}]]]},
                 {Entity2, [count: []]},
                 {Entity2, [one: []]}
               ])
    end

    test "records stages called through the module, trust and the values a stage was given" do
      outer_name = {:attribute, {:outer, 1, :name}}

      assert recorded_shapes(Module4) ==
               Enum.sort([
                 {Entity26, [filter: [[any: {[:messages], [body: {:==, outer_name}]}]]]},
                 {Entity2, [sort: [[c: :desc]]]},
                 {Entity2,
                  [
                    sort: [[c: :desc]],
                    paginate: [[page: %Placeholder{name: :pinned}, size: 10]]
                  ]},
                 {Entity2, [filter: [[b: {:in, 1..3}]]]},
                 {Entity2, [filter: [[b: {:in, 1..3}]], take: [2]]},
                 {Entity2, [trust: [], filter: [[b: {:>=, -1}, c: {:==, "x"}]]]}
               ])
    end

    # Range.new/3 raises on a step of 0, which belongs to the stage's own expansion to report, not to
    # recording - so recording builds no range with it. Recorded from the module body, which is open
    # and expands no `..//`.
    test "records a range the stage refuses, raising on nothing" do
      module = Hologram.Query.ShapeTest.RangeModule

      source = """
      defmodule #{inspect(module)} do
        Hologram.Query.Shape.record(
          :filter,
          [quote(do: Hologram.Test.Fixtures.Entity.Module2), quote(do: b in 1..10//0)],
          __ENV__
        )
      end
      """

      Code.compile_string(source)

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      assert recorded_shapes(module) == [
               {Entity2, [filter: [[b: {:in, %Range{first: 1, last: 10, step: 0}}]]]}
             ]
    end

    test "records nothing, raising nothing, into a module no longer open" do
      query = quote(do: Hologram.Test.Fixtures.Entity.Module2)

      assert record(:take, [query, 1], __ENV__) == :ok

      attributes = __MODULE__.__info__(:attributes)
      refute Keyword.has_key?(attributes, attribute())
    end
  end

  describe "replay/1" do
    test "replays the stages into the normalized query term" do
      predicates = [a: {:==, %Placeholder{name: :a}}]

      term =
        Entity2
        |> Stage.filter(predicates)
        |> Stage.take(5)
        |> Stage.normalize()

      assert replay({Entity2, [filter: [predicates], take: [5]]}) == {:ok, term}
    end

    test "replays a range with pinned bounds into the comparisons a range gives" do
      bounds = [{:>=, %Placeholder{name: :lo}}, {:<=, %Placeholder{name: :hi}}]

      {:ok, replayed} = replay({Entity2, [filter: [[b: bounds]]]})

      range_filter =
        Entity2
        |> Stage.filter(b: {:in, 1..3})
        |> Stage.normalize()
        |> Map.fetch!(:filter)

      assert replayed.filter == [{:b, :<=, {:placeholder, :hi}}, {:b, :>=, {:placeholder, :lo}}]
      assert range_filter == [{:b, :<=, 3}, {:b, :>=, 1}]
    end

    test "replays pinned pagination options into placeholder bounds" do
      opts = %Placeholder{name: :opts}

      assert {:ok, %{skip: {:placeholder, :opts}, take: {:placeholder, :opts}}} =
               replay({Entity2, [paginate: [[page: opts, size: opts]]]})
    end

    test "returns :error when a stage refuses the shape" do
      assert replay({Entity2, [filter: [[unknown: {:==, 1}]]]}) == :error
    end

    test "returns :error when the alias names no entity type" do
      assert replay({Enum, [take: [1]]}) == :error
    end
  end
end
