defmodule Hologram.Query.RegistryTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Query.Registry

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  describe "build/1" do
    test "builds entries with the term and its param shape" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}
      term_id = id(term)

      assert build([term]) == %{
               term_id => %{param_shape: %{search: :string}, term: term, window: nil}
             }
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
end
