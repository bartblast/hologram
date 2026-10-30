defmodule Hologram.Query.RegistryTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Query.Registry

  alias Hologram.Query.Stage
  alias Hologram.Query.Window
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Policy

  describe "build/2" do
    test "builds entries with the term, its placeholder shape, and the window it downloads" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      window = Window.derive(term, false)

      assert build([term], false) == %{
               id(term) => %{
                 placeholder_shape: %{search: :string},
                 term: term,
                 window: window,
                 window_id: id(window)
               }
             }
    end

    test "gives queries downloading the same rows one window between them" do
      searched_term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      chosen_term = %{Stage.normalize(Module2) | filter: [{:a, :==, {:placeholder, :flag}}]}

      registry = build([searched_term, chosen_term], false)

      assert map_size(registry) == 2

      assert registry[id(searched_term)].window_id == registry[id(chosen_term)].window_id
    end

    test "collapses structurally equal terms into one entry" do
      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      registry = build([term, term], false)

      assert map_size(registry) == 1
    end

    test "derives each window with whether a client checks permissions" do
      term = Stage.normalize(Policy.Module1)
      window = Window.derive(term, true)

      entry = build([term], true)[id(term)]

      assert entry.window == window
      assert entry.window_id == id(window)
    end
  end

  describe "entity_types/1" do
    test "returns the type a term reads" do
      term = Stage.normalize(Module2)

      assert entity_types(term) == MapSet.new([Module2])
    end

    test "returns the types a term includes alongside its own" do
      term =
        Module3
        |> include(a)
        |> Stage.normalize()

      assert entity_types(term) == MapSet.new([Module2, Module3])
    end

    test "returns the types a path in the filter goes through" do
      term = %{Stage.normalize(Module5) | filter: [{[:a, :b, :c], :==, "x"}]}

      assert entity_types(term) == MapSet.new([Module2, Module3, Module5])
    end

    test "returns the types a path operand goes through" do
      term = %{Stage.normalize(Module3) | filter: [{:c_id, :==, {:attribute, [:b, :id]}}]}

      assert entity_types(term) == MapSet.new([Module2, Module3])
    end

    test "walks includes to any depth" do
      term =
        Module5
        |> include(a, &include(&1, b))
        |> Stage.normalize()

      assert entity_types(term) == MapSet.new([Module2, Module3, Module5])
    end
  end

  describe "id/1" do
    test "changes with the term" do
      first_term = Stage.normalize(Module2)

      second_term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      refute id(first_term) == id(second_term)
    end

    test "returns a lowercase hex string of the truncated SHA-256" do
      term = Stage.normalize(Module2)

      assert id(term) == "34af1788d77dce8ba5bdcbf857ad4c22"
    end
  end

  describe "placeholder_shape/1" do
    test "binds membership element placeholders with the attribute type" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 1]}]}

      assert placeholder_shape(term) == %{bound: :integer}
    end

    test "collects no type for a triple keyed by a placeholder" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{{:placeholder, :field}, :==, {:placeholder, :value}}]
      }

      assert placeholder_shape(term) == %{}
    end

    test "collects no type for a membership list under a placeholder key" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{{:placeholder, :field}, :in, [1, {:placeholder, :value}]}]
      }

      assert placeholder_shape(term) == %{}
    end

    test "collects placeholders from nested includes" do
      base_term =
        Module3
        |> include(a)
        |> Stage.normalize()

      sub_term = %{base_term.include.a | filter: [{:c, :==, {:placeholder, :search}}]}
      term = %{base_term | include: %{a: sub_term}}

      assert placeholder_shape(term) == %{search: :string}
    end

    test "collects placeholders inside a disjunction" do
      term = %{
        Stage.normalize(Module2)
        | filter: [
            {:or, [[{:b, :>=, {:placeholder, :min}}], [{:c, :==, {:placeholder, :search}}]]}
          ]
      }

      assert placeholder_shape(term) == %{min: :integer, search: :string}
    end

    test "dedups a placeholder met several times with one type" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{:b, :>=, {:placeholder, :bound}}, {:b, :<, {:placeholder, :bound}}]
      }

      assert placeholder_shape(term) == %{bound: :integer}
    end

    test "derives list types for membership placeholders" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      assert placeholder_shape(term) == %{ids: {:list, :integer}}
    end

    test "derives placeholder types from the attributes met" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{:b, :>=, {:placeholder, :min}}, {:c, :==, {:placeholder, :search}}]
      }

      assert placeholder_shape(term) == %{min: :integer, search: :string}
    end

    test "derives placeholder types through a path from the attribute it ends at" do
      term = %{
        Stage.normalize(Module3)
        | filter: [
            {[:b, :b], :in, {:placeholder, :counts}},
            {[:b, :c], :==, {:placeholder, :search}}
          ]
      }

      assert placeholder_shape(term) == %{counts: {:list, :integer}, search: :string}
    end

    test "derives system attribute placeholder types" do
      term = %{Stage.normalize(Module2) | filter: [{:id, :==, {:placeholder, :entity_id}}]}

      assert placeholder_shape(term) == %{entity_id: :uuid}
    end

    test "derives to-one reference field placeholder types" do
      term = %{Stage.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target_id}}]}

      assert placeholder_shape(term) == %{target_id: :uuid}
    end

    test "returns an empty shape for queries without placeholders" do
      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      assert placeholder_shape(term) == %{}
    end

    test "keeps a placeholder's real type when it also stands under a placeholder key" do
      term = %{
        Stage.normalize(Module2)
        | filter: [
            {:b, :==, {:placeholder, :value}},
            {{:placeholder, :field}, :==, {:placeholder, :value}}
          ]
      }

      assert placeholder_shape(term) == %{value: :integer}
    end

    test "raises on conflicting placeholder types" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{:c, :==, {:placeholder, :value}}, {:b, :==, {:placeholder, :value}}]
      }

      expected_msg =
        "placeholder :value binds as :string and :integer - rename one of the conflicting variables"

      assert_error Hologram.CompileError, expected_msg, fn ->
        placeholder_shape(term)
      end
    end
  end
end
