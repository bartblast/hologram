defmodule Hologram.Query.RegistryTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Query.Registry

  alias Hologram.Query
  alias Hologram.Query.Window
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5

  describe "build/1" do
    test "builds entries with the term, its placeholder shape, and the window it downloads" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      window = Window.derive(term)

      assert build([term]) == %{
               id(term) => %{
                 placeholder_shape: %{search: :string},
                 term: term,
                 window: window,
                 window_id: id(window)
               }
             }
    end

    test "gives queries downloading the same rows one window between them" do
      searched_term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      chosen_term = %{Query.normalize(Module2) | filter: [{:a, :==, {:placeholder, :flag}}]}

      registry = build([searched_term, chosen_term])

      assert map_size(registry) == 2

      assert registry[id(searched_term)].window_id == registry[id(chosen_term)].window_id
    end

    test "collapses structurally equal terms into one entry" do
      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      registry = build([term, term])

      assert map_size(registry) == 1
    end
  end

  describe "entity_types/1" do
    test "returns the type a term reads" do
      term = Query.normalize(Module2)

      assert entity_types(term) == MapSet.new([Module2])
    end

    test "returns the types a term includes alongside its own" do
      term =
        Module3
        |> include(:a)
        |> Query.normalize()

      assert entity_types(term) == MapSet.new([Module2, Module3])
    end

    test "walks includes to any depth" do
      term =
        Module5
        |> include(:a, &include(&1, :b))
        |> Query.normalize()

      assert entity_types(term) == MapSet.new([Module2, Module3, Module5])
    end
  end

  describe "id/1" do
    test "changes with the term" do
      first_term = Query.normalize(Module2)

      second_term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      refute id(first_term) == id(second_term)
    end

    test "computes a stable lowercase hex id" do
      term = Query.normalize(Module2)

      assert id(term) == id(term)
      assert id(term) =~ ~r/^[0-9a-f]{32}$/
    end
  end

  describe "placeholder_shape/1" do
    test "binds membership element placeholders with the attribute type" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 1]}]}

      assert placeholder_shape(term) == %{bound: :integer}
    end

    test "collects no type for a triple keyed by a placeholder" do
      term = %{
        Query.normalize(Module2)
        | filter: [{{:placeholder, :field}, :==, {:placeholder, :value}}]
      }

      assert placeholder_shape(term) == %{}
    end

    test "collects no type for a membership list under a placeholder key" do
      term = %{
        Query.normalize(Module2)
        | filter: [{{:placeholder, :field}, :in, [1, {:placeholder, :value}]}]
      }

      assert placeholder_shape(term) == %{}
    end

    test "collects placeholders from nested includes" do
      base_term =
        Module3
        |> include(:a)
        |> Query.normalize()

      sub_term = %{base_term.include.a | filter: [{:c, :==, {:placeholder, :search}}]}
      term = %{base_term | include: %{a: sub_term}}

      assert placeholder_shape(term) == %{search: :string}
    end

    test "dedups a placeholder met several times with one type" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :>=, {:placeholder, :bound}}, {:b, :<, {:placeholder, :bound}}]
      }

      assert placeholder_shape(term) == %{bound: :integer}
    end

    test "derives list types for membership placeholders" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      assert placeholder_shape(term) == %{ids: {:list, :integer}}
    end

    test "derives placeholder types from the attributes met" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :>=, {:placeholder, :min}}, {:c, :==, {:placeholder, :search}}]
      }

      assert placeholder_shape(term) == %{min: :integer, search: :string}
    end

    test "derives system attribute placeholder types" do
      term = %{Query.normalize(Module2) | filter: [{:id, :==, {:placeholder, :entity_id}}]}

      assert placeholder_shape(term) == %{entity_id: :uuid}
    end

    test "derives to-one reference field placeholder types" do
      term = %{Query.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target_id}}]}

      assert placeholder_shape(term) == %{target_id: :uuid}
    end

    test "returns an empty shape for queries without placeholders" do
      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      assert placeholder_shape(term) == %{}
    end

    test "keeps a placeholder's real type when it also stands under a placeholder key" do
      term = %{
        Query.normalize(Module2)
        | filter: [
            {:b, :==, {:placeholder, :value}},
            {{:placeholder, :field}, :==, {:placeholder, :value}}
          ]
      }

      assert placeholder_shape(term) == %{value: :integer}
    end

    test "raises on conflicting placeholder types" do
      term = %{
        Query.normalize(Module2)
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
