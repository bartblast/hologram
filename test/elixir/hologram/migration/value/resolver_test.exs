defmodule Hologram.Migration.Value.ResolverTest.OtherCalendar do
  @moduledoc false

  # Calendar.ISO under another name: a value in a calendar that isn't ISO but compares with it.
  defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

  defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
    to: Calendar.ISO

  defdelegate valid_date?(year, month, day), to: Calendar.ISO
  defdelegate valid_time?(hour, minute, second, microsecond), to: Calendar.ISO
end

defmodule Hologram.Migration.Value.ResolverTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Value.Resolver

  alias Hologram.Migration.Value
  alias Hologram.Test.Fixtures.Migration.Module2

  @uuid "018f0000-0000-7000-8000-000000000000"

  @model %{
    entities: %{
      MyApp.Stop => %{
        attributes: [
          {:code, :integer, []},
          {:currency, :string, []},
          {:price, :float, []},
          {:state, :enum, [values: [:draft, :live]]}
        ],
        relationships: [{:guide, MyApp.User, []}, {:trip, MyApp.Trip, []}],
        roles: [],
        uniques: []
      },
      MyApp.Tag => %{
        attributes: [{:name, :string, []}],
        relationships: [],
        roles: [],
        uniques: []
      },
      MyApp.Trip => %{
        attributes: [
          {:budget, :float, []},
          {:destination, :string, []},
          {:external_id, :uuid, []},
          {:kind, :enum, [values: [:draft, :live, :old]]},
          {:nickname, :string, []},
          {:seats, :integer, []},
          {:state, :enum, [values: [:draft, :live]]},
          {:wide_state, :enum, [values: [:archived, :draft, :live]]}
        ],
        relationships: [
          {:owner, MyApp.User, []},
          {:parent, MyApp.Trip, []},
          {:stops, [MyApp.Stop], []},
          {:tags, [MyApp.Tag], []}
        ],
        roles: [],
        uniques: []
      },
      MyApp.User => %{
        attributes: [{:name, :string, []}],
        relationships: [{:manager, MyApp.User, []}],
        roles: [],
        uniques: []
      }
    },
    roles: %{},
    user_entity: nil
  }

  defp attribute_target(type, opts \\ []) do
    %{kind: :attribute, line: 9, name: :value, opts: opts, type: type}
  end

  defp refusal(term, target) do
    error =
      assert_raise Hologram.CompileError, fn ->
        resolve!(%Value{term: term}, @model, MyApp.Trip, target)
      end

    prefix = "the backfill of :value on MyApp.Trip (line 9) "

    assert String.starts_with?(error.message, prefix)

    String.replace_prefix(error.message, prefix, "")
  end

  defp relationship_target(type) do
    %{kind: :relationship, line: 9, name: :value, type: type}
  end

  defp resolved(term, target), do: resolve!(%Value{term: term}, @model, MyApp.Trip, target)

  describe "storable?/1" do
    test "takes the earliest date" do
      assert storable?(~D[-4713-11-24])
    end

    test "refuses a date before it" do
      refute storable?(~D[-4713-11-23])
    end

    test "takes the earliest datetime" do
      assert storable?(~U[-4713-11-24 00:00:00Z])
    end

    test "refuses a datetime before it" do
      refute storable?(~U[-4713-11-23 23:59:59Z])
    end

    test "takes the latest date a column holds" do
      assert storable?(Date.new!(5_874_897, 12, 31))
    end

    test "refuses a date past it" do
      refute storable?(Date.new!(5_874_898, 1, 1))
    end

    test "takes the latest datetime the codec encodes" do
      assert storable?(~U[9999-12-31 23:59:59.999999Z])
    end

    test "refuses a datetime past it" do
      date = Date.new!(10_000, 1, 1)

      refute storable?(DateTime.new!(date, ~T[00:00:00]))
    end

    test "refuses a date in another calendar" do
      refute storable?(%{~D[2026-01-02] | calendar: MyApp.Calendar})
    end

    test "refuses a time in another calendar" do
      refute storable?(%{~T[10:00:00] | calendar: MyApp.Calendar})
    end

    test "refuses a datetime in another calendar" do
      refute storable?(%{~U[2026-01-02 10:00:00Z] | calendar: MyApp.Calendar})
    end

    test "refuses a datetime with an offset that is no integer" do
      refute storable?(%{~U[2026-01-02 10:00:00Z] | std_offset: "0"})
    end

    test "refuses a partial date struct" do
      refute storable?(%{__struct__: Date})
    end

    test "refuses a partial datetime struct" do
      refute storable?(%{__struct__: DateTime, calendar: Calendar.ISO})
    end

    test "takes a time" do
      assert storable?(~T[10:00:00])
    end

    test "refuses a string holding a NUL" do
      refute storable?(<<"a", 0>>)
    end

    test "takes a plain string" do
      assert storable?("a")
    end

    test "takes any other value" do
      assert storable?(1)
    end
  end

  describe "resolve!/4, names" do
    test "reads an attribute" do
      assert resolved({:name, [:destination]}, attribute_target(:string)) == %{
               term: {:name, [:destination], :string},
               type: :string
             }
    end

    test "reads an id" do
      assert %{type: :uuid} = resolved({:name, [:id]}, attribute_target(:uuid))
    end

    for name <- [:created_at, :server_created_at, :server_updated_at, :updated_at] do
      test "reads #{name}" do
        assert %{type: :datetime} =
                 resolved({:name, [unquote(name)]}, attribute_target(:datetime))
      end
    end

    test "reads a to-one's reference" do
      assert %{term: {:name, [:owner_id], {:reference, MyApp.User}}} =
               resolved({:name, [:owner_id]}, relationship_target(MyApp.User))
    end

    test "reads through a to-one" do
      assert %{term: {:name, [:owner, :name], :string}} =
               resolved({:name, [:owner, :name]}, attribute_target(:string))
    end

    test "reads through two to-ones" do
      assert %{term: {:name, [:parent, :owner, :name], :string}} =
               resolved({:name, [:parent, :owner, :name]}, attribute_target(:string))
    end

    test "reads a reference through a to-one" do
      assert %{type: {:reference, MyApp.User}} =
               resolved({:name, [:parent, :owner_id]}, relationship_target(MyApp.User))
    end

    test "refuses a name the type doesn't have, listing what it has" do
      assert refusal({:name, [:nope]}, attribute_target(:string)) ==
               "reads :nope, which MyApp.Trip doesn't have at this op - it has: budget, " <>
                 "created_at, destination, external_id, id, kind, nickname, owner, owner_id, " <>
                 "parent, parent_id, seats, server_created_at, server_updated_at, state, stops, " <>
                 "tags, updated_at, wide_state"
    end

    test "refuses a name the hop's type doesn't have" do
      assert refusal({:name, [:owner, :nope]}, attribute_target(:string)) =~
               "reads :nope, which MyApp.User doesn't have at this op - it has:"
    end

    test "refuses an unknown hop" do
      assert refusal({:name, [:nope, :name]}, attribute_target(:string)) =~
               "reads :nope, which MyApp.Trip doesn't have"
    end

    test "refuses a path through a string, with no Elixir spelling to offer" do
      assert refusal({:name, [:destination, :length]}, attribute_target(:integer)) ==
               "reads through :destination of MyApp.Trip, a field - a path reads through to-one " <>
                 "relationships"
    end

    test "refuses a path through the row's date or time, pointing to a fn" do
      assert refusal({:name, [:created_at, :year]}, attribute_target(:integer)) ==
               "reads through :created_at of MyApp.Trip, a field - a path reads through to-one " <>
                 "relationships, and a part of a date or time is read in a fn with Map.fetch!/2"
    end

    test "offers no fn for a related row's date, which a fn can't name" do
      refute refusal({:name, [:owner, :created_at, :year]}, attribute_target(:integer)) =~ "fn"
    end

    test "refuses a path through a reference, naming the relationship" do
      assert refusal({:name, [:owner_id, :name]}, attribute_target(:string)) ==
               "reads through :owner_id of MyApp.Trip, a field - a path reads through to-one " <>
                 "relationships, so read through owner, not owner_id"
    end

    test "names only the relationship for a reference after a hop" do
      assert refusal({:name, [:parent, :owner_id, :name]}, attribute_target(:string)) =~
               "reads through :owner_id of MyApp.Trip, a field - a path reads through to-one " <>
                 "relationships, so read through owner, not owner_id"
    end

    test "refuses reading through a to-one sharing its name with an attribute" do
      model =
        update_in(
          @model.entities[MyApp.Trip].attributes,
          &[{:owner, :string, [optional: true]} | &1]
        )

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(
            %Value{term: {:name, [:owner, :name]}},
            model,
            MyApp.Trip,
            attribute_target(:string)
          )
        end

      assert error.message =~ "both a relationship and a field at this op"
    end

    test "refuses reading through a to-one named like another's reference" do
      model =
        update_in(
          @model.entities[MyApp.Trip].relationships,
          &[{:owner_id, MyApp.User, [optional: true]} | &1]
        )

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(
            %Value{term: {:name, [:owner_id, :name]}},
            model,
            MyApp.Trip,
            attribute_target(:string)
          )
        end

      assert error.message =~ "both a relationship and a field at this op"
    end

    test "refuses a set sharing its name with an attribute" do
      model =
        update_in(
          @model.entities[MyApp.Trip].attributes,
          &[{:tags, :string, [optional: true]} | &1]
        )

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(
            %Value{term: {:count, {:relationship, [:tags]}}},
            model,
            MyApp.Trip,
            attribute_target(:integer)
          )
        end

      assert error.message =~ "both a relationship and a field at this op"
    end

    test "refuses a hop to a type the model no longer has" do
      model = update_in(@model.entities, &Map.delete(&1, MyApp.User))

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(
            %Value{term: {:name, [:owner, :name]}},
            model,
            MyApp.Trip,
            attribute_target(:string)
          )
        end

      assert error.message =~ "reads MyApp.User, which doesn't exist at this op"
    end

    test "refuses a to-one read by its own name, naming its reference" do
      assert refusal({:name, [:owner]}, relationship_target(MyApp.User)) ==
               "reads :owner of MyApp.Trip, a to-one, as a value - its reference is owner_id"
    end

    test "refuses a to-many read as a value" do
      assert refusal({:name, [:tags]}, attribute_target(:string)) ==
               "reads :tags of MyApp.Trip, a to-many, as a value - read it with count or " <>
                 "most_common"
    end

    test "refuses a path through a to-many" do
      assert refusal({:name, [:tags, :name]}, attribute_target(:string)) ==
               "reads through :tags of MyApp.Trip, a to-many - a path reads through to-one " <>
                 "relationships"
    end

    test "refuses a reference through a to-many's name" do
      assert refusal({:name, [:tags_id]}, attribute_target(:uuid)) =~ "reads :tags_id"
    end
  end

  describe "resolve!/4, types" do
    test "refuses a result of another type" do
      assert refusal({:name, [:seats]}, attribute_target(:string)) ==
               "gives a value of type :integer where a value of type :string goes"
    end

    test "doesn't widen an integer field into a float" do
      assert refusal({:name, [:seats]}, attribute_target(:float)) ==
               "gives a value of type :integer where a value of type :float goes"
    end

    test "copies an enum into one holding all its values" do
      target = attribute_target(:enum, values: [:archived, :draft, :live])

      assert %{type: {:enum, MyApp.Trip, :state, [:draft, :live]}} =
               resolved({:name, [:state]}, target)
    end

    test "refuses an enum into one missing some of its values" do
      target = attribute_target(:enum, values: [:draft])

      assert refusal({:name, [:state]}, target) ==
               "gives the enum :state of MyApp.Trip where the enum :value of MyApp.Trip goes"
    end

    test "refuses an enum into a string" do
      assert refusal({:name, [:state]}, attribute_target(:string)) =~ "gives the enum :state"
    end

    test "reads a reference into a uuid attribute" do
      assert %{type: :uuid} = resolved({:name, [:owner_id]}, attribute_target(:uuid))
    end

    test "refuses a reference to another type" do
      assert refusal({:name, [:owner_id]}, relationship_target(MyApp.Trip)) ==
               "gives a reference to MyApp.User where a reference to MyApp.Trip goes"
    end

    test "reads the row's id into a reference to its own type" do
      assert %{type: {:reference, MyApp.Trip}} =
               resolved({:name, [:id]}, relationship_target(MyApp.Trip))
    end

    test "refuses the row's id into a reference to another type" do
      assert refusal({:name, [:id]}, relationship_target(MyApp.User)) ==
               "gives a value of type :uuid where a reference to MyApp.User goes"
    end

    test "refuses a uuid attribute into a reference" do
      assert refusal({:name, [:external_id]}, relationship_target(MyApp.User)) =~
               "gives a value of type :uuid"
    end
  end

  describe "resolve!/4, values" do
    test "types a value by a sibling of the target's type" do
      assert resolved(
               {:coalesce, [{:name, [:nickname]}, {:value, "x"}]},
               attribute_target(:string)
             ) ==
               %{
                 term: {:coalesce, [{:name, [:nickname], :string}, {:value, "x", :string}]},
                 type: :string
               }
    end

    test "widens an integer literal where a float goes" do
      assert %{term: {:coalesce, [_budget, {:value, +0.0, :float}]}} =
               resolved({:coalesce, [{:name, [:budget]}, {:value, 0}]}, attribute_target(:float))
    end

    test "refuses an integer a float can't hold exactly" do
      term = {:coalesce, [{:name, [:budget]}, {:value, 9_007_199_254_740_993}]}

      assert refusal(term, attribute_target(:float)) ==
               "holds 9007199254740993, which isn't a value of type :float"
    end

    test "refuses a value of another type" do
      term = {:coalesce, [{:name, [:seats]}, {:value, "none"}]}

      assert refusal(term, attribute_target(:integer)) ==
               ~s(holds "none", which isn't a value of type :integer)
    end

    test "refuses nil" do
      term = {:coalesce, [{:name, [:nickname]}, {:value, nil}]}

      assert refusal(term, attribute_target(:string)) ==
               "holds nil - nil is the absence a backfill exists to fill"
    end

    test "takes the earliest date PostgreSQL stores" do
      term = {:coalesce, [{:name, [:created_on]}, {:value, ~D[-4713-11-24]}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:created_on, :date, []}])

      assert %{type: :date} =
               resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:date))
    end

    test "stores a pinned datetime in another calendar as UTC ISO" do
      iso = ~U[2026-01-01 03:06:07Z]
      value = %{iso | calendar: Value.ResolverTest.OtherCalendar}
      term = {:coalesce, [{:name, [:due]}, {:value, value}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:due, :datetime, []}])

      assert %{term: {:coalesce, [_due, {:value, stored, :datetime}]}} =
               resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:datetime))

      assert stored == Value.normalize_constant(iso, :datetime)
    end

    test "refuses a datetime whose calendar throws while printing it" do
      value = %{
        ~U[2026-01-01 00:00:00Z]
        | year: 10_000,
          calendar: Module2
      }

      term = {:coalesce, [{:name, [:due]}, {:value, value}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:due, :datetime, []}])

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:datetime))
        end

      assert error.message =~ "holds %{"
      assert error.message =~ "which isn't a value of type :datetime"
    end

    test "refuses a date before PostgreSQL's earliest" do
      term = {:coalesce, [{:name, [:created_on]}, {:value, ~D[-4713-11-23]}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:created_on, :date, []}])

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:date))
        end

      assert error.message =~ "which isn't a value of type :date"
    end

    test "refuses a datetime before PostgreSQL's earliest" do
      term = {:coalesce, [{:name, [:created_at]}, {:value, ~U[-4713-11-23 23:59:59Z]}]}

      assert refusal(term, attribute_target(:datetime)) =~
               "which isn't a value of type :datetime"
    end

    test "refuses a datetime with malformed offsets, naming the member" do
      value = %{~U[2026-01-01 00:00:00Z] | utc_offset: nil}
      term = {:coalesce, [{:name, [:created_at]}, {:value, value}]}

      assert refusal(term, attribute_target(:datetime)) =~ "which isn't a value of type :datetime"
    end

    test "refuses a date in a calendar that doesn't exist, naming the member" do
      value = %{~D[2026-01-01] | calendar: Nope.Calendar}
      term = {:coalesce, [{:name, [:created_on]}, {:value, value}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:created_on, :date, []}])

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:date))
        end

      assert error.message =~ "which isn't a value of type :date"
    end

    test "holds a datetime in UTC at microsecond precision, as a column gives it back" do
      offset = %{
        ~U[2026-01-01 12:00:00Z]
        | utc_offset: 3600,
          zone_abbr: "CET",
          time_zone: "Europe/Warsaw"
      }

      term = {:coalesce, [{:name, [:created_at]}, {:value, offset}]}

      assert %{term: {:coalesce, [_field, {:value, value, :datetime}]}} =
               resolved(term, attribute_target(:datetime))

      assert value == ~U[2026-01-01 11:00:00.000000Z]
    end

    test "holds a time at microsecond precision, as a column gives it back" do
      term = {:coalesce, [{:name, [:starts]}, {:value, ~T[10:00:00]}]}
      model = put_in(@model.entities[MyApp.Trip].attributes, [{:starts, :time, []}])

      assert %{term: {:coalesce, [_field, {:value, value, :time}]}} =
               resolve!(%Value{term: term}, model, MyApp.Trip, attribute_target(:time))

      assert value == ~T[10:00:00.000000]
    end

    test "refuses a string PostgreSQL can't store" do
      term = {:coalesce, [{:name, [:nickname]}, {:value, <<"a", 0>>}]}

      assert refusal(term, attribute_target(:string)) =~ "which isn't a value of type :string"
    end

    test "refuses invalid UTF-8" do
      term = {:coalesce, [{:name, [:nickname]}, {:value, <<255>>}]}

      assert refusal(term, attribute_target(:string)) =~ "which isn't a value of type :string"
    end

    test "refuses an integer past the column's range" do
      term = {:coalesce, [{:name, [:seats]}, {:value, 9_223_372_036_854_775_808}]}

      assert refusal(term, attribute_target(:integer)) =~ "which isn't a value of type :integer"
    end

    test "types a literal by its sibling enum, not the target" do
      target = attribute_target(:enum, values: [:archived, :draft, :live])

      assert %{term: {:coalesce, [_state, {:value, :live, {:enum, MyApp.Trip, :state, _values}}]}} =
               resolved({:coalesce, [{:name, [:state]}, {:value, :live}]}, target)
    end

    test "refuses a literal outside its sibling enum, even when the target has it" do
      target = attribute_target(:enum, values: [:archived, :draft, :live])

      assert refusal({:coalesce, [{:name, [:state]}, {:value, :archived}]}, target) ==
               "holds :archived, which isn't the enum :state of MyApp.Trip"
    end

    test "lowercases a uuid" do
      upcased = String.upcase(@uuid)
      term = {:coalesce, [{:name, [:owner_id]}, {:value, upcased}]}

      assert %{term: {:coalesce, [_owner_id, {:value, @uuid, {:reference, MyApp.User}}]}} =
               resolved(term, relationship_target(MyApp.User))
    end

    test "refuses a reference value that is no uuid" do
      term = {:coalesce, [{:name, [:owner_id]}, {:value, "nope"}]}

      assert refusal(term, relationship_target(MyApp.User)) ==
               ~s(holds "nope", which isn't a reference to MyApp.User)
    end
  end

  describe "resolve!/4, <>" do
    test "resolves its operands as strings" do
      term = {:concat, [{:value, "to "}, {:name, [:destination]}]}

      assert resolved(term, attribute_target(:string)) == %{
               term: {:concat, [{:value, "to ", :string}, {:name, [:destination], :string}]},
               type: :string
             }
    end

    test "refuses an operand that is no string" do
      term = {:concat, [{:value, "seats: "}, {:name, [:seats]}]}

      assert refusal(term, attribute_target(:string)) ==
               "gives a value of type :integer where a value of type :string goes"
    end

    test "refuses a non-string literal" do
      term = {:concat, [{:value, 1}, {:name, [:destination]}]}

      assert refusal(term, attribute_target(:string)) ==
               "holds 1, which isn't a value of type :string"
    end

    test "refuses a string result into another type" do
      term = {:concat, [{:name, [:destination]}, {:value, "!"}]}

      assert refusal(term, attribute_target(:integer)) =~ "gives a value of type :string"
    end
  end

  describe "resolve!/4, split and at" do
    defp at(text, separator, position),
      do: {:at, {:split, text, {:value, separator}}, {:value, position}}

    test "resolves to a string" do
      assert resolved(at({:name, [:destination]}, ", ", 1), attribute_target(:string)) == %{
               term:
                 {:at, {:split, {:name, [:destination], :string}, {:value, ", ", :string}},
                  {:value, 1, :integer}},
               type: :string
             }
    end

    test "refuses text that is no string" do
      assert refusal(at({:name, [:seats]}, ",", 0), attribute_target(:string)) =~
               "gives a value of type :integer"
    end

    test "refuses a pinned empty separator" do
      assert refusal(at({:name, [:destination]}, "", 0), attribute_target(:string)) ==
               ~s(splits by "" - split takes a non-empty string)
    end

    test "refuses a pinned separator that is no string" do
      assert refusal(at({:name, [:destination]}, 1, 0), attribute_target(:string)) ==
               "splits by 1 - split takes a non-empty string"
    end

    test "refuses a pinned negative position" do
      assert refusal(at({:name, [:destination]}, ",", -1), attribute_target(:string)) ==
               "reads position -1 - at takes an integer from 0 to 1000000"
    end

    test "refuses a pinned position past the largest" do
      assert refusal(at({:name, [:destination]}, ",", 1_000_001), attribute_target(:string)) =~
               "reads position 1000001"
    end

    test "refuses a pinned separator and position whose calendar throws while printing them" do
      value = %{~U[2026-01-01 00:00:00Z] | calendar: Module2}

      assert refusal(at({:name, [:destination]}, value, 0), attribute_target(:string)) =~
               "splits by %{"

      assert refusal(at({:name, [:destination]}, ",", value), attribute_target(:string)) =~
               "reads position %{"
    end

    test "refuses a pinned position that is no integer" do
      assert refusal(at({:name, [:destination]}, ",", "0"), attribute_target(:string)) =~
               ~s(reads position "0")
    end
  end

  describe "resolve!/4, coalesce" do
    test "refuses values of different types" do
      term = {:coalesce, [{:name, [:nickname]}, {:name, [:seats]}]}

      assert refusal(term, attribute_target(:string)) ==
               "mixes a value of type :string and a value of type :integer in coalesce - its " <>
                 "values share one type"
    end

    test "refuses two enum attributes, each a type of its own" do
      term = {:coalesce, [{:name, [:state]}, {:name, [:kind]}]}
      target = attribute_target(:enum, values: [:draft, :live, :old])

      assert refusal(term, target) =~ "mixes the enum :state of MyApp.Trip and the enum :kind"
    end

    test "shares a reference between a reference and the id on a self-relationship" do
      term = {:coalesce, [{:name, [:parent_id]}, {:name, [:id]}]}

      assert %{type: {:reference, MyApp.Trip}} = resolved(term, relationship_target(MyApp.Trip))
    end

    test "types literals alone by the target" do
      assert %{term: {:coalesce, [{:value, "a", :string}, {:value, "b", :string}]}} =
               resolved({:coalesce, [{:value, "a"}, {:value, "b"}]}, attribute_target(:string))
    end

    test "types a nested coalesce of literals by its siblings" do
      target = attribute_target(:enum, values: [:archived, :draft, :live])
      term = {:coalesce, [{:name, [:state]}, {:coalesce, [{:value, :draft}, {:value, :live}]}]}

      enum = {:enum, MyApp.Trip, :state, [:draft, :live]}

      assert %{
               term:
                 {:coalesce,
                  [_state, {:coalesce, [{:value, :draft, ^enum}, {:value, :live, ^enum}]}]},
               type: ^enum
             } = resolved(term, target)
    end

    test "nests" do
      term =
        {:coalesce, [{:coalesce, [{:name, [:nickname]}, {:name, [:destination]}]}, {:value, "x"}]}

      assert %{type: :string} = resolved(term, attribute_target(:string))
    end
  end

  describe "resolve!/4, count" do
    test "counts a stored to-many" do
      assert resolved({:count, {:relationship, [:tags]}}, attribute_target(:integer)) == %{
               term: {:count, {:relationship, [:tags]}},
               type: :integer
             }
    end

    test "counts a to-many through a to-one" do
      assert %{type: :integer} =
               resolved({:count, {:relationship, [:parent, :tags]}}, attribute_target(:integer))
    end

    test "refuses a count into another type" do
      assert refusal({:count, {:relationship, [:tags]}}, attribute_target(:float)) =~
               "gives a value of type :integer"
    end

    test "refuses a to-one" do
      assert refusal({:count, {:relationship, [:owner]}}, attribute_target(:integer)) ==
               "counts or groups :owner of MyApp.Trip, a to-one - a set is a stored to-many"
    end

    test "refuses an attribute" do
      assert refusal({:count, {:relationship, [:seats]}}, attribute_target(:integer)) ==
               "reads :seats of MyApp.Trip, a field, as a set - a set is a stored to-many"
    end

    test "refuses a system field" do
      assert refusal({:count, {:relationship, [:created_at]}}, attribute_target(:integer)) =~
               "a field, as a set"
    end

    test "refuses a reference" do
      assert refusal({:count, {:relationship, [:owner_id]}}, attribute_target(:integer)) =~
               "a field, as a set"
    end

    test "refuses a path through a field" do
      assert refusal({:count, {:relationship, [:destination, :tags]}}, attribute_target(:integer)) ==
               "reads through :destination of MyApp.Trip, a field - a path reads through to-one " <>
                 "relationships"
    end

    test "offers no Elixir spelling for a set read through a date" do
      refute refusal({:count, {:relationship, [:created_at, :tags]}}, attribute_target(:integer)) =~
               "Map.fetch!"
    end

    test "refuses an unknown name" do
      assert refusal({:count, {:relationship, [:nope]}}, attribute_target(:integer)) =~
               "reads :nope, which MyApp.Trip doesn't have"
    end

    test "refuses a path through a to-many" do
      assert refusal({:count, {:relationship, [:stops, :trip]}}, attribute_target(:integer)) =~
               "reads through :stops of MyApp.Trip, a to-many"
    end

    test "refuses an unknown hop" do
      assert refusal({:count, {:relationship, [:nope, :tags]}}, attribute_target(:integer)) =~
               "reads :nope, which MyApp.Trip doesn't have"
    end
  end

  describe "resolve!/4, a fn's arguments and the rows pointing at this one" do
    defp resolve_on(entity, value, type) do
      target = %{kind: :attribute, line: 7, name: :value, opts: [], type: type}

      resolve!(value, @model, entity, target)
    end

    defp resolve_refusal(entity, value, type) do
      error = assert_raise Hologram.CompileError, fn -> resolve_on(entity, value, type) end

      error.message
    end

    test "accepts arguments naming fields and relationships" do
      value = %Value{args: [:destination, :owner_id, :parent, :tags, :id], term: {:name, [:id]}}

      assert %{type: :uuid} = resolve_on(MyApp.Trip, value, :uuid)
    end

    test "refuses an argument the row doesn't have" do
      value = %Value{args: [:destination, :nope], term: {:name, [:destination]}}

      assert resolve_refusal(MyApp.Trip, value, :string) =~ "reads :nope, which MyApp.Trip"
    end

    test "names an Elixir spelling for a path on a plain field of a fn" do
      value = %Value{args: [:created_at], term: {:name, [:created_at, :year]}}

      assert resolve_refusal(MyApp.Trip, value, :integer) =~
               "read it in Elixir, like fn created_at -> Map.fetch!(created_at, :year) end"
    end

    test "gives no Elixir spelling for a path past a self-relationship" do
      value = %Value{args: [:parent], term: {:name, [:parent, :created_at, :year]}}

      message = resolve_refusal(MyApp.Trip, value, :integer)

      assert message =~ "reads through :created_at of MyApp.Trip, a field"
      refute message =~ "Map.fetch!"
    end

    test "gives no Elixir spelling for a later hop named like the path's first" do
      model =
        @model
        |> put_in([:entities, MyApp.User, :attributes], [{:guide, :datetime, []}])
        |> put_in([:entities, MyApp.Trip, :relationships], [{:guide, MyApp.User, []}])

      value = %Value{args: [:guide], term: {:name, [:guide, :guide, :year]}}
      target = %{kind: :attribute, line: 7, name: :value, opts: [], type: :integer}

      error =
        assert_raise Hologram.CompileError, fn ->
          resolve!(value, model, MyApp.Trip, target)
        end

      assert error.message =~ "reads through :guide of MyApp.User, a field"
      refute error.message =~ "Map.fetch!"
    end

    test "resolves an Elixir fn over the row's own fields, typed as the target" do
      term = {:function, MyApp.M, :__backfill_0__, [:destination, :owner_id, :id]}
      value = %Value{args: [:destination, :owner_id, :id], term: term}

      assert resolve_on(MyApp.Trip, value, :string) == %{
               term:
                 {:function, MyApp.M, :__backfill_0__, [:destination, :owner_id, :id], :string},
               type: :string
             }
    end

    test "refuses a relationship as an argument of an Elixir fn" do
      term = {:function, MyApp.M, :__backfill_0__, [:tags]}
      value = %Value{args: [:tags], term: term}

      assert resolve_refusal(MyApp.Trip, value, :string) =~
               "takes :tags, a relationship, in an Elixir fn"
    end

    test "counts the rows pointing at this one" do
      value = %Value{args: [:id], term: {:count, {:referencing, MyApp.Stop, :trip}}}

      assert resolve_on(MyApp.Trip, value, :integer) == %{
               term: {:count, {:referencing, MyApp.Stop, :trip}},
               type: :integer
             }
    end

    test "types a most_common over them by the attribute of the queried type" do
      value = %Value{
        args: [:id],
        term: {:most_common, {:referencing, MyApp.Stop, :trip}, :currency}
      }

      assert %{
               term: {:most_common, {:referencing, MyApp.Stop, :trip}, :currency, :string, nil},
               type: :string
             } = resolve_on(MyApp.Trip, value, :string)
    end

    test "refuses a type the model doesn't have" do
      value = %Value{args: [:id], term: {:count, {:referencing, MyApp.Nope, :trip}}}

      assert resolve_refusal(MyApp.Trip, value, :integer) =~
               "reads MyApp.Nope, which doesn't exist at this op"
    end

    test "refuses a reference the queried type doesn't have" do
      value = %Value{args: [:id], term: {:count, {:referencing, MyApp.Stop, :nope}}}

      assert resolve_refusal(MyApp.Trip, value, :integer) =~
               "by nope_id, but MyApp.Stop has no to-one nope at this op"
    end

    test "refuses a reference pointing at another type" do
      value = %Value{args: [:id], term: {:count, {:referencing, MyApp.Stop, :guide}}}

      assert resolve_refusal(MyApp.Trip, value, :integer) =~
               "by guide_id, which points at MyApp.User, not at MyApp.Trip"
    end
  end

  describe "resolve!/4, most_common" do
    test "takes the attribute's type" do
      assert resolved({:most_common, {:relationship, [:tags]}, :name}, attribute_target(:string)) ==
               %{
                 term: {:most_common, {:relationship, [:tags]}, :name, :string, nil},
                 type: :string
               }
    end

    test "embeds an enum's declared values as ranks" do
      target = attribute_target(:enum, values: [:draft, :live])

      assert %{term: {:most_common, _set, :state, _type, [:draft, :live]}} =
               resolved({:most_common, {:relationship, [:stops]}, :state}, target)
    end

    test "takes a reference" do
      assert %{type: {:reference, MyApp.User}} =
               resolved(
                 {:most_common, {:relationship, [:stops]}, :guide_id},
                 relationship_target(MyApp.User)
               )
    end

    test "takes an integer" do
      assert %{type: :integer} =
               resolved(
                 {:most_common, {:relationship, [:stops]}, :code},
                 attribute_target(:integer)
               )
    end

    test "refuses a float" do
      assert refusal({:most_common, {:relationship, [:stops]}, :price}, attribute_target(:float)) =~
               "the database groups 0.0 with -0.0"
    end

    test "refuses an attribute the set's rows don't have" do
      assert refusal({:most_common, {:relationship, [:tags]}, :nope}, attribute_target(:string)) =~
               "reads :nope, which MyApp.Tag doesn't have"
    end

    test "refuses a result of another type" do
      assert refusal({:most_common, {:relationship, [:tags]}, :name}, attribute_target(:integer)) =~
               "gives a value of type :string"
    end

    test "refuses a set that is no to-many" do
      assert refusal({:most_common, {:relationship, [:owner]}, :name}, attribute_target(:string)) =~
               "a set is a stored to-many"
    end
  end
end
