defmodule Hologram.Migration.Value.CheckTest.OtherCalendar do
  @moduledoc false

  # Calendar.ISO under another name: a bound in a calendar that isn't ISO but compares with it.
  defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

  defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
    to: Calendar.ISO

  defdelegate valid_date?(year, month, day), to: Calendar.ISO
  defdelegate valid_time?(hour, minute, second, microsecond), to: Calendar.ISO
end

defmodule Hologram.Migration.Value.CheckTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Value.Check

  alias Hologram.Migration.Value

  @uuid "018f0000-0000-7000-8000-000000000000"

  @model %{
    entities: %{
      MyApp.Task => %{
        attributes: [
          {:code, :string, [optional: true]},
          {:rank, :integer, []},
          {:title, :string, []}
        ],
        relationships: [
          {:owner, MyApp.User, [optional: true]},
          {:reviewer, MyApp.User, []},
          {:tags, [MyApp.User], []}
        ],
        roles: [],
        uniques: []
      },
      MyApp.User => %{attributes: [], relationships: [], roles: [], uniques: []}
    },
    roles: %{},
    user_entity: nil
  }

  defp add_attribute(type, opts) do
    %{op: :add_attribute, entity: MyApp.Task, name: :value, type: type, opts: opts, line: 7}
  end

  defp add_relationship(type, opts) do
    %{op: :add_relationship, entity: MyApp.Task, name: :link, type: type, opts: opts, line: 7}
  end

  defp change(kind, name, changes) do
    %{op: kind, entity: MyApp.Task, name: name, changes: changes, line: 7}
  end

  defp check(op), do: validate_ops!([op], @model)

  defp refusal(op) do
    error = assert_raise Hologram.CompileError, fn -> check(op) end

    error.message
  end

  describe "validate_ops!/2, ops with no backfill" do
    test "passes an op carrying none" do
      assert check(add_attribute(:string, optional: true)) == :ok
    end

    test "passes an op that carries no options" do
      op = %{op: :delete_attribute, entity: MyApp.Task, name: :code, line: 7}

      assert validate_ops!([op], @model) == :ok
    end
  end

  describe "validate_ops!/2, where a backfill may be written" do
    test "takes one on a change turning an optional attribute required" do
      assert check(change(:change_attribute, :code, optional: false, backfill: "x")) == :ok
    end

    test "takes one on a change turning an optional relationship required" do
      assert check(change(:change_relationship, :owner, optional: false, backfill: @uuid)) == :ok
    end

    test "refuses one beside a type change" do
      op = change(:change_attribute, :code, type: :integer, optional: false, backfill: 1)

      assert refusal(op) =~ "sits beside a type change - change the type in an op of its own"
    end

    test "refuses one on a change that doesn't turn the member required" do
      assert refusal(change(:change_attribute, :code, max_length: 3, backfill: "x")) =~
               "add optional: false to the op"
    end

    test "refuses one on a change keeping the member optional" do
      assert refusal(change(:change_attribute, :code, optional: true, backfill: "x")) =~
               "add optional: false to the op"
    end

    test "refuses one when a repeated option leaves the member optional" do
      op = change(:change_attribute, :code, optional: true, optional: false, backfill: "x")

      assert refusal(op) =~ "add optional: false to the op"
    end

    test "refuses one on an attribute already required" do
      assert refusal(change(:change_attribute, :title, optional: false, backfill: "x")) ==
               "the backfill of :title on MyApp.Task (line 7) fills a member that is already " <>
                 "required, so no row holds nil"
    end

    test "refuses one on a relationship already required" do
      assert refusal(change(:change_relationship, :reviewer, optional: false, backfill: @uuid)) =~
               "already required"
    end

    test "refuses nil on a change" do
      assert refusal(change(:change_attribute, :code, optional: false, backfill: nil)) =~
               "is nil - a backfill is the value rows receive"
    end

    test "refuses nil on an added relationship" do
      assert refusal(add_relationship(MyApp.User, optional: true, backfill: nil)) =~ "is nil"
    end

    test "refuses a constant on a to-many" do
      assert refusal(add_relationship([MyApp.User], backfill: @uuid)) =~
               "fills a to-many relationship"
    end

    test "refuses a computed one on a to-many" do
      value = %Value{term: {:name, [:owner_id]}}

      assert refusal(add_relationship([MyApp.User], backfill: value)) =~
               "fills a to-many relationship"
    end
  end

  describe "validate_ops!/2, a computed backfill" do
    test "resolves against the model before the op" do
      value = %Value{term: {:name, [:title]}}

      assert check(add_attribute(:string, backfill: value)) == :ok
    end

    test "refuses a name the model lacks" do
      value = %Value{term: {:name, [:nope]}}

      assert refusal(add_attribute(:string, backfill: value)) =~ "reads :nope"
    end

    test "refuses a name only the op itself adds" do
      value = %Value{term: {:name, [:value]}}

      assert refusal(add_attribute(:string, backfill: value)) =~ "reads :value"
    end

    test "refuses a result of another type" do
      value = %Value{term: {:name, [:rank]}}

      assert refusal(add_attribute(:string, backfill: value)) =~
               "gives a value of type :integer where a value of type :string goes"
    end
  end

  describe "validate_ops!/2, a constant on a relationship" do
    test "takes a uuid" do
      assert check(add_relationship(MyApp.User, optional: true, backfill: @uuid)) == :ok
    end

    test "refuses anything else" do
      assert refusal(add_relationship(MyApp.User, optional: true, backfill: "nope")) ==
               ~s|the backfill of :link on MyApp.Task (line 7) holds "nope", which isn't the | <>
                 "id of a MyApp.User"
    end

    test "takes an uppercase uuid, which the fill stores in lowercase" do
      op = add_relationship(MyApp.User, optional: true, backfill: String.upcase(@uuid))

      assert check(op) == :ok
      assert [%{backfill: {:constant, @uuid}}] = Value.fills([op], @model)
    end
  end

  # An applied migration can't be edited and every replay judges it again, so a value accepted
  # here must stay accepted. A failure means a change would refuse files that already passed.
  describe "validate_ops!/2, the boundaries applied files rely on" do
    for {label, type, opts, value} <- [
          {"min", :integer, [min: 2], 2},
          {"max", :integer, [max: 2], 2},
          {"float min", :float, [min: 1.5], 1.5},
          {"date max", :date, [max: ~D[2026-01-01]], ~D[2026-01-01]},
          {"in", :integer, [in: 1..2], 2},
          {"length in code points", :string, [length: 2], "éé"},
          {"min_length", :string, [min_length: 2], "ab"},
          {"max_length", :string, [max_length: 2], "éé"},
          {"format", :string, [format: ~r/^a/i], "Abc"},
          {"enum", :enum, [values: [:a, :b]], :b},
          {"the largest integer", :integer, [], 9_223_372_036_854_775_807},
          {"the smallest integer", :integer, [], -9_223_372_036_854_775_808},
          {"the earliest date", :date, [], ~D[-4713-11-24]},
          {"the earliest datetime", :datetime, [], ~U[-4713-11-24 00:00:00Z]},
          {"the latest datetime", :datetime, [], ~U[9999-12-31 23:59:59.999999Z]},
          {"a unique string", :string, [unique: true], String.duplicate("a", 2692)}
        ] do
      test "keeps accepting #{label}" do
        op =
          add_attribute(unquote(type), [
            {:backfill, unquote(Macro.escape(value))} | unquote(Macro.escape(opts))
          ])

        assert check(op) == :ok
      end
    end

    test "keeps accepting the latest date" do
      assert check(add_attribute(:date, backfill: Date.new!(5_874_897, 12, 31))) == :ok
    end

    test "keeps the share of a key two strings split" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 1335)),
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :other,
          type: :string,
          opts: [optional: true],
          line: 8
        },
        %{op: :add_unique, entity: MyApp.Task, fields: [:other, :value], line: 9}
      ]

      assert validate_ops!(ops, @model) == :ok
    end

    test "keeps the share of a key a string splits with an integer" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 2673)),
        %{op: :add_unique, entity: MyApp.Task, fields: [:rank, :value], line: 8}
      ]

      assert validate_ops!(ops, @model) == :ok
    end
  end

  describe "validate_ops!/2, a constant against the declared rules" do
    for {label, type, opts, good, bad, expected} <- [
          {"min", :integer, [min: 2], 2, 1, "must be at least 2"},
          {"max", :integer, [max: 2], 2, 3, "must be at most 2"},
          {"in", :integer, [in: 1..2], 2, 3, "must be in 1..2"},
          {"length", :string, [length: 2], "ab", "a", "must be exactly 2 characters"},
          {"min_length", :string, [min_length: 2], "ab", "a", "must be at least 2 characters"},
          {"max_length", :string, [max_length: 2], "ab", "abc", "must be at most 2 characters"},
          {"enum values", :enum, [values: [:a]], :a, :b, "must be one of [:a]"},
          {"type", :integer, [], 1, "x", "must be of type :integer"}
        ] do
      test "takes a value within #{label}" do
        op =
          add_attribute(unquote(type), [{:backfill, unquote(good)} | unquote(Macro.escape(opts))])

        assert check(op) == :ok
      end

      test "refuses a value breaking #{label}" do
        op =
          add_attribute(unquote(type), [{:backfill, unquote(bad)} | unquote(Macro.escape(opts))])

        assert refusal(op) =~ unquote(expected)
      end
    end

    test "names the value, the attribute, the type and the rule" do
      assert refusal(add_attribute(:string, max_length: 2, backfill: "long")) ==
               ~s|the backfill of :value on MyApp.Task (line 7) holds "long", which as a | <>
                 ":string must be at most 2 characters"
    end

    for {label, type, opts, value} <- [
          {"a length rule on an integer", :integer, [max_length: 2], 1},
          {"a format on an integer", :integer, [format: ~r/a/], 1},
          {"a bound of the wrong type", :date, [min: 1], ~D[2026-01-01]},
          {"a bound on a string", :string, [min: 1], "a"},
          {"an in that is no range", :integer, [in: 5], 1},
          {"an in on a string", :string, [in: 1..2], "a"},
          {"a format that is no regex", :string, [format: "^a"], "a"},
          {"a stored format that doesn't compile", :string, [format: {:regex, "(", []}], "a"},
          {"a length that is no integer", :string, [max_length: "2"], "abcdef"},
          {"a negative length", :string, [min_length: -1], "a"},
          {"a stored format with a bad flag", :string, [format: {:regex, "a", [:nope]}], "a"},
          {"a stored format with a text flag", :string, [format: {:regex, "a", ["i"]}], "a"},
          {"a range with a step that is no integer", :integer,
           [in: %{__struct__: Range, first: 1, last: 5, step: "x"}], 1},
          {"a range of floats", :integer,
           [in: %{__struct__: Range, first: 1.0, last: 5.0, step: 1}], 1},
          {"a range with a zero step", :integer,
           [in: %{__struct__: Range, first: 1, last: 5, step: 0}], 1},
          {"a date bound in a calendar that doesn't exist", :date,
           [min: %{~D[2020-01-01] | calendar: Nope}], ~D[2026-01-01]}
        ] do
      test "refuses #{label} instead of crashing" do
        op =
          add_attribute(unquote(type), [
            {:backfill, unquote(Macro.escape(value))} | unquote(Macro.escape(opts))
          ])

        assert refusal(op) =~ "attribute can't take"
      end
    end

    test "reads a format the model stores as its pattern and flags" do
      model =
        put_in(
          @model.entities[MyApp.Task].attributes,
          [{:code, :string, [format: {:regex, "^a", [:caseless]}, optional: true]}]
        )

      good = change(:change_attribute, :code, optional: false, backfill: "Abc")
      bad = change(:change_attribute, :code, optional: false, backfill: "bcd")

      assert validate_ops!([good], model) == :ok

      error = assert_raise Hologram.CompileError, fn -> validate_ops!([bad], model) end

      assert error.message =~ "must match"
    end

    test "reads the rules as the op's own changes leave them" do
      op = change(:change_attribute, :code, optional: false, max_length: 1, backfill: "ab")

      assert refusal(op) =~ "must be at most 1 characters"
    end

    test "refuses a string past a unique index's byte bound" do
      op = add_attribute(:string, unique: true, backfill: String.duplicate("a", 2693))

      assert refusal(op) =~ "must hold at most 2692 bytes"
    end

    test "refuses a string past the bound of a unique index a later op adds" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 2693)),
        change(:change_attribute, :value, unique: true)
      ]

      error = assert_raise Hologram.CompileError, fn -> validate_ops!(ops, @model) end

      assert error.message =~ "must hold at most 2692 bytes"
    end

    test "follows a rename to the unique key a later op adds" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 2000)),
        %{op: :rename_attribute, entity: MyApp.Task, from: :value, to: :renamed, line: 8},
        %{op: :add_unique, entity: MyApp.Task, fields: [:renamed, :title], line: 9}
      ]

      error = assert_raise Hologram.CompileError, fn -> validate_ops!(ops, @model) end

      assert error.message =~ "must hold at most"
    end

    test "follows a rename of the entity type" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 2693)),
        %{op: :rename_entity, from: MyApp.Task, to: MyApp.Job, line: 8},
        %{
          op: :change_attribute,
          entity: MyApp.Job,
          name: :value,
          changes: [unique: true],
          line: 9
        }
      ]

      assert_raise Hologram.CompileError, ~r/must hold at most 2692 bytes/, fn ->
        validate_ops!(ops, @model)
      end
    end

    test "has no bound once a later op deletes the member" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 3000)),
        %{op: :delete_attribute, entity: MyApp.Task, name: :value, line: 8}
      ]

      assert validate_ops!(ops, @model) == :ok
    end

    test "ignores a later column that takes the deleted member's name" do
      ops = [
        add_attribute(:string, optional: true, backfill: String.duplicate("a", 3000)),
        %{op: :delete_attribute, entity: MyApp.Task, name: :value, line: 8},
        %{
          op: :add_attribute,
          entity: MyApp.Task,
          name: :value,
          type: :string,
          opts: [optional: true, unique: true],
          line: 9
        }
      ]

      assert validate_ops!(ops, @model) == :ok
    end

    test "takes a string at the byte bound" do
      assert check(add_attribute(:string, unique: true, backfill: String.duplicate("a", 2692))) ==
               :ok
    end

    test "measures the bound in bytes" do
      op = add_attribute(:string, unique: true, backfill: String.duplicate("é", 1347))

      assert refusal(op) =~ "must hold at most 2692 bytes"
    end

    test "refuses a string holding a NUL byte" do
      assert refusal(add_attribute(:string, backfill: <<"a", 0>>)) =~
               "which the database can't store as a :string"
    end

    test "refuses a date PostgreSQL can't store" do
      assert refusal(add_attribute(:date, backfill: ~D[-4713-11-23])) =~
               "which the database can't store as a :date"
    end

    test "refuses a malformed datetime without crashing" do
      value = %{~U[2026-01-01 00:00:00Z] | utc_offset: nil}

      assert refusal(add_attribute(:datetime, backfill: value)) =~ ":datetime"
    end

    for {label, value, type} <- [
          {"date", %{~D[2026-01-01] | calendar: Nope}, :date},
          {"datetime", %{~U[2026-01-01 00:00:00Z] | calendar: Nope}, :datetime},
          {"time", %{~T[10:00:00] | calendar: Nope}, :time}
        ] do
      test "refuses a #{label} in a calendar that doesn't exist" do
        op = add_attribute(unquote(type), backfill: unquote(Macro.escape(value)))

        assert refusal(op) =~ "must be of type #{inspect(unquote(type))}"
      end
    end

    test "refuses a NUL string on an enum without crashing" do
      assert refusal(add_attribute(:enum, values: [:a], backfill: <<"a", 0>>)) =~
               "must be of type :enum"
    end

    test "takes a date bound in another calendar, as a declaration may" do
      bound = %{~D[2020-01-01] | calendar: Hologram.Migration.Value.CheckTest.OtherCalendar}

      assert check(add_attribute(:date, min: bound, backfill: ~D[2026-01-01])) == :ok
    end

    test "takes a date bound PostgreSQL can't store, as a declaration may" do
      assert check(add_attribute(:date, min: ~D[-9000-01-01], backfill: ~D[2026-01-01])) == :ok
    end

    test "lowercases a uuid attribute" do
      op = add_attribute(:uuid, optional: true, backfill: String.upcase(@uuid))

      assert check(op) == :ok
      assert [%{backfill: {:constant, @uuid}}] = Value.fills([op], @model)
    end

    test "refuses a partial date struct without crashing" do
      value = %{__struct__: Date}

      assert refusal(add_attribute(:date, backfill: value)) =~ "must be of type :date"
    end

    test "takes an integer where a float goes" do
      assert check(add_attribute(:float, min: 0.0, backfill: 1)) == :ok
    end

    test "judges a widened integer by the rules" do
      assert refusal(add_attribute(:float, min: 2.0, backfill: 1)) =~ "must be at least 2.0"
    end
  end
end
