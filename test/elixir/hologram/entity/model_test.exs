defmodule Hologram.Entity.ModelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Model

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module2

  describe "empty/0" do
    test "returns a model with no entity types" do
      assert empty() == %{}
    end
  end

  describe "from_modules/1" do
    test "derives an entry for an entity type without declarations" do
      assert from_modules([Module1]) == %{
               Module1 => %{attributes: [], relationships: [], roles: []}
             }
    end

    test "derives attributes sorted by name" do
      assert from_modules([Module2]) == %{
               Module2 => %{
                 attributes: [
                   {:a, :boolean, [default: false]},
                   {:b, :integer, [optional: true]},
                   {:c, :string, []}
                 ],
                 relationships: [],
                 roles: []
               }
             }
    end

    test "derives relationships and roles with opts sorted by key" do
      assert from_modules([Module13]) == %{
               Module13 => %{
                 attributes: [
                   {:priority, :integer, [optional: true]},
                   {:public, :boolean, [default: false]},
                   {:title, :string, []}
                 ],
                 relationships: [{:parent, Module1, [optional: true]}],
                 roles: [{:editor, []}, {:owner, [creator: true, extends: :editor]}]
               }
             }
    end

    test "returns equal terms regardless of the given module order" do
      assert from_modules([Module13, Module2]) == from_modules([Module2, Module13])
    end
  end
end
