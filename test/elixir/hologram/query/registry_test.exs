defmodule Hologram.Query.RegistryTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Query.Registry

  alias Hologram.Query
  alias Hologram.Query.Window
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5

  describe "build/1" do
    test "builds entries with the term, its param shape, and the window it downloads" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}
      window = Window.derive(term)

      assert build([term]) == %{
               id(term) => %{
                 param_shape: %{search: :string},
                 term: term,
                 window: window,
                 window_id: id(window)
               }
             }
    end

    test "gives queries downloading the same rows one window between them" do
      searched_term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}
      chosen_term = %{Query.normalize(Module2) | filter: [{:a, :==, {:param, :flag}}]}

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

  describe "param_shape/1" do
    test "binds membership element params with the attribute type" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [{:param, :bound}, 1]}]}

      assert param_shape(term) == %{bound: :integer}
    end

    test "collects params from nested includes" do
      base_term =
        Module3
        |> include(:a)
        |> Query.normalize()

      sub_term = %{base_term.include.a | filter: [{:c, :==, {:param, :search}}]}
      term = %{base_term | include: %{a: sub_term}}

      assert param_shape(term) == %{search: :string}
    end

    test "dedups a param met several times with one type" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :>=, {:param, :bound}}, {:b, :<, {:param, :bound}}]
      }

      assert param_shape(term) == %{bound: :integer}
    end

    test "derives list types for membership params" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:param, :ids}}]}

      assert param_shape(term) == %{ids: {:list, :integer}}
    end

    test "derives param types from the attributes met" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :>=, {:param, :min}}, {:c, :==, {:param, :search}}]
      }

      assert param_shape(term) == %{min: :integer, search: :string}
    end

    test "derives system attribute param types" do
      term = %{Query.normalize(Module2) | filter: [{:id, :==, {:param, :entity_id}}]}

      assert param_shape(term) == %{entity_id: :uuid}
    end

    test "derives to-one reference field param types" do
      term = %{Query.normalize(Module3) | filter: [{:c_id, :==, {:param, :target_id}}]}

      assert param_shape(term) == %{target_id: :uuid}
    end

    test "returns an empty shape for queries without params" do
      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      assert param_shape(term) == %{}
    end

    test "raises on conflicting param types" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:c, :==, {:param, :value}}, {:b, :==, {:param, :value}}]
      }

      expected_msg =
        "param :value binds as :string and :integer - rename one of the conflicting variables"

      assert_error Hologram.CompileError, expected_msg, fn ->
        param_shape(term)
      end
    end
  end

  describe "sort_key_attributes/1" do
    test "collects pairs ordered on string attributes" do
      term =
        Module2
        |> order_by(:c)
        |> Query.normalize()

      assert sort_key_attributes([term]) == MapSet.new([{Module2, :c}])
    end

    test "deduplicates pairs across terms" do
      term_1 =
        Module2
        |> order_by(:c)
        |> Query.normalize()

      term_2 =
        Module2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      assert sort_key_attributes([term_1, term_2]) == MapSet.new([{Module2, :c}])
    end

    test "skips natively-ordered attribute types" do
      term =
        Module2
        |> order_by(:b)
        |> Query.normalize()

      assert sort_key_attributes([term]) == MapSet.new()
    end

    test "walks include sub-terms" do
      term =
        Module3
        |> include(:a, fn sub_query -> order_by(sub_query, :c) end)
        |> Query.normalize()

      assert sort_key_attributes([term]) == MapSet.new([{Module2, :c}])
    end
  end
end
