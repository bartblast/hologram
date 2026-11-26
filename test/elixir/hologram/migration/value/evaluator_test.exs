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

    test "doesn't compute a coalesce's fallback once a value isn't nil" do
      term = {:coalesce, [{:name, [:active], :boolean}, {:name, [:place, :open], :boolean}]}

      # The fallback can't be read from this row, so computing it would raise.
      assert evaluate(term, %{active: false, place: :unreadable}) == false
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
      # More nils than "b"s, so counting nil would give nil.
      row = %{
        tags: [%{name: "a"}, %{name: "b"}, %{name: "b"}, %{name: nil}, %{name: nil}, %{name: nil}]
      }

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

  describe "evaluate/2 and reads/1, an Elixir fn" do
    test "calls the function with the row's values, in argument order" do
      term = {:function, String, :replace_suffix, [:title, :suffix, :with], :string}

      assert evaluate(term, %{title: "a.txt", suffix: ".txt", with: ".md"}) == "a.md"
    end

    test "gives what the function returns as its type stores it" do
      uuid = "0B9E3C5A-4C8F-4A1E-9F3D-2B6A7C8D9E0F"
      stored = String.downcase(uuid)

      assert evaluate({:function, String, :upcase, [:id], :uuid}, %{id: stored}) == stored

      id = "02wLIRxqmq3AUo6vl2OW36"

      assert evaluate({:function, String, :trim, [:id], {:reference, MyApp.User}}, %{id: id}) ==
               id

      assert evaluate({:function, Kernel, :abs, [:n], :float}, %{n: -2}) === 2.0

      assert evaluate({:function, DateTime, :from_naive!, [:at, :zone], :datetime}, %{
               at: ~N[2026-01-01 12:00:00],
               zone: "Etc/UTC"
             }) == ~U[2026-01-01 12:00:00.000000Z]

      assert evaluate({:function, Time, :from_iso8601!, [:at], :time}, %{at: "12:00:00"}) ==
               ~T[12:00:00.000000]
    end

    test "reads nothing beyond the row's own fields" do
      assert reads({:function, String, :upcase, [:title], :string}) == %{}
    end
  end

  describe "evaluate/2 and reads/1, the rows pointing at this one" do
    @set {:referencing, MyApp.Stop, :trip}

    test "counts them, none included" do
      assert evaluate({:count, @set}, %{{MyApp.Stop, :trip} => [%{}, %{}]}) == 2
      assert evaluate({:count, @set}, %{{MyApp.Stop, :trip} => []}) == 0
    end

    test "picks the most common value among them" do
      rows = [%{currency: "b"}, %{currency: "a"}, %{currency: "b"}]
      term = {:most_common, @set, :currency, :string, nil}

      assert evaluate(term, %{{MyApp.Stop, :trip} => rows}) == "b"
    end

    test "names them in the reads, under the type and the to-one" do
      assert reads({:count, @set}) == %{{MyApp.Stop, :trip} => %{}}

      assert reads({:most_common, @set, :currency, :string, nil}) ==
               %{{MyApp.Stop, :trip} => %{}}
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
