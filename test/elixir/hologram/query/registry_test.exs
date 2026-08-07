defmodule Hologram.Query.RegistryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Registry

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  describe "param_shape/1" do
    test "collects params from nested includes" do
      base_term =
        Module3
        |> Query.include(:a)
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
        |> Query.filter(a: true)
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
