defmodule Hologram.Migration.Value.EvaluatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Value.Evaluator

  @enum {:enum, MyApp.Stop, :state, [:live, :draft]}

  defp at(text, separator, position) do
    {:at, {:split, text, {:value, separator, :string}}, {:value, position, :integer}}
  end

  describe "evaluate/2" do
    test "gives a value" do
      assert evaluate({:value, "a", :string}, %{}) == "a"
    end

    test "reads a field of the row" do
      assert evaluate({:name, [:title], :string}, %{title: "a"}) == "a"
    end

    test "reads nil from a nil field" do
      assert evaluate({:name, [:title], :string}, %{title: nil}) == nil
    end

    test "reads through a to-one" do
      row = %{owner: %{name: "a"}}

      assert evaluate({:name, [:owner, :name], :string}, row) == "a"
    end

    test "reads through two to-ones" do
      row = %{parent: %{owner: %{name: "a"}}}

      assert evaluate({:name, [:parent, :owner, :name], :string}, row) == "a"
    end

    test "gives nil through a nil to-one" do
      assert evaluate({:name, [:owner, :name], :string}, %{owner: nil}) == nil
    end

    test "gives nil through a nil hop further along" do
      row = %{parent: %{owner: nil}}

      assert evaluate({:name, [:parent, :owner, :name], :string}, row) == nil
    end

    test "joins strings" do
      term = {:concat, [{:value, "to ", :string}, {:name, [:city], :string}]}

      assert evaluate(term, %{city: "Porto"}) == "to Porto"
    end

    test "gives nil for a join with a nil operand" do
      term = {:concat, [{:value, "to ", :string}, {:name, [:city], :string}]}

      assert evaluate(term, %{city: nil}) == nil
    end

    test "picks a part of a split" do
      term = at({:name, [:destination], :string}, ", ", 1)

      assert evaluate(term, %{destination: "Porto, Portugal"}) == "Portugal"
    end

    test "gives nil past the end of a split" do
      term = at({:name, [:destination], :string}, ", ", 1)

      assert evaluate(term, %{destination: "Porto"}) == nil
    end

    test "gives nil for a split of nil" do
      term = at({:name, [:destination], :string}, ", ", 0)

      assert evaluate(term, %{destination: nil}) == nil
    end

    test "gives the empty string for the first part of an empty string" do
      term = at({:name, [:destination], :string}, ", ", 0)

      assert evaluate(term, %{destination: ""}) == ""
    end

    test "gives the first non-nil value of a coalesce" do
      term = {:coalesce, [{:name, [:nickname], :string}, {:value, "none", :string}]}

      assert evaluate(term, %{nickname: nil}) == "none"
      assert evaluate(term, %{nickname: "a"}) == "a"
    end

    test "counts a set" do
      assert evaluate({:count, {:relationship, [:tags]}}, %{tags: [%{}, %{}]}) == 2
    end

    test "counts a set through a to-one" do
      row = %{parent: %{tags: [%{}]}}

      assert evaluate({:count, {:relationship, [:parent, :tags]}}, row) == 1
    end

    test "counts 0 through a nil to-one" do
      assert evaluate({:count, {:relationship, [:parent, :tags]}}, %{parent: nil}) == 0
    end

    test "gives the most common value of a set" do
      term = {:most_common, {:relationship, [:tags]}, :name, :string, nil}
      row = %{tags: [%{name: "a"}, %{name: "b"}, %{name: "b"}, %{name: nil}]}

      assert evaluate(term, row) == "b"
    end

    test "gives nil for the most common value of no rows" do
      term = {:most_common, {:relationship, [:tags]}, :name, :string, nil}

      assert evaluate(term, %{tags: []}) == nil
    end

    test "orders an enum tie by the declared values" do
      term = {:most_common, {:relationship, [:stops]}, :state, @enum, [:live, :draft]}

      assert evaluate(term, %{stops: [%{state: :draft}, %{state: :live}]}) == :live
    end

    test "nests" do
      term =
        {:coalesce,
         [
           {:concat, [{:name, [:first], :string}, {:name, [:owner, :last], :string}]},
           at({:name, [:destination], :string}, ",", 0)
         ]}

      assert evaluate(term, %{first: nil, owner: nil, destination: "a,b"}) == "a"
    end
  end

  describe "reads/1" do
    test "reads nothing for a value" do
      assert reads({:value, "a", :string}) == %{}
    end

    test "reads nothing for the row's own field" do
      assert reads({:name, [:title], :string}) == %{}
    end

    test "reads the hops of a path" do
      assert reads({:name, [:parent, :owner, :name], :string}) == %{parent: %{owner: %{}}}
    end

    test "reads a set" do
      assert reads({:count, {:relationship, [:tags]}}) == %{tags: %{}}
    end

    test "reads the hops to a set" do
      assert reads({:most_common, {:relationship, [:parent, :tags]}, :name, :string, nil}) ==
               %{parent: %{tags: %{}}}
    end

    test "reads through a split" do
      assert reads(at({:name, [:owner, :city], :string}, ",", 0)) == %{owner: %{}}
    end

    test "merges what the operands read" do
      term =
        {:coalesce,
         [
           {:name, [:parent, :owner, :name], :string},
           {:concat, [{:name, [:parent, :title], :string}, {:name, [:owner, :name], :string}]},
           {:count, {:relationship, [:parent, :tags]}}
         ]}

      assert reads(term) == %{owner: %{}, parent: %{owner: %{}, tags: %{}}}
    end
  end
end
