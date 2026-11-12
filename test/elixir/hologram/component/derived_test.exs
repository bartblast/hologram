defmodule Hologram.Component.DerivedTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Component.Derived

  alias Hologram.Component.NotComputed
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Component.Module37
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Page.Module17

  defp entry(name, type, args, function, reads_state \\ false) do
    %{args: args, function: function, name: name, reads_state: reads_state, type: type}
  end

  defp no_query(_name, _args, _term), do: raise("no query was expected")

  defp compute_plain(entries, props, state \\ %{}, computed \\ %{}) do
    compute(entries, Module37, props, state, computed, plain_opts())
  end

  defp plain_opts, do: [registered_query?: fn _name -> false end, run_query: &no_query/3]

  defp query_opts(run_query), do: [registered_query?: fn _name -> true end, run_query: run_query]

  describe "compute/6" do
    test "computes the fields in order, each reading the fields before it" do
      entries = [
        entry(:double, :integer, [:count], &(&1 * 2)),
        entry(:quadruple, :integer, [:double], &(&1 * 2))
      ]

      assert compute_plain(entries, %{count: 3}) == %{double: 6, quadruple: 12}
    end

    test "reads props, state and the fields computed before" do
      entries = [entry(:total, :integer, [:count, :step, :base], &(&1 + &2 + &3))]

      assert compute_plain(entries, %{count: 1}, %{step: 2}, %{base: 3}) == %{
               base: 3,
               total: 6
             }
    end

    test "hands a query result to the run_query option, normalized" do
      entries = [
        entry(:entities, [Entity2], [:count], fn _count -> filter(Entity2, a == true) end)
      ]

      run_query = fn name, args, term -> {name, args, term} end

      term =
        Entity2
        |> filter(a == true)
        |> Stage.normalize()

      assert compute(entries, Module37, %{count: 3}, %{}, %{}, query_opts(run_query)) == %{
               entities: {:entities, [3], term}
             }
    end

    test "hands an entity type result to the run_query option as a query of every row" do
      entries = [entry(:entities, [Entity2], [], fn -> Entity2 end)]

      run_query = fn _name, _args, term -> term end

      assert compute(entries, Module37, %{}, %{}, %{}, query_opts(run_query)) == %{
               entities: Stage.normalize(Entity2)
             }
    end

    test "raises on a query of another shape than the type" do
      entries = [entry(:total, :integer, [], fn -> filter(Entity2, a == true) end)]

      expected_msg =
        "derived field :total in Hologram.Test.Fixtures.Component.Module37 is declared :integer, but its query is a set of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute(entries, Module37, %{}, %{}, %{}, query_opts(&no_query/3))
      end
    end

    test "hands a query of one row to the run_query option for a field declared as one row" do
      entries = [entry(:first, Entity2, [], fn -> one(Entity2) end)]

      run_query = fn _name, _args, term -> term end

      term =
        Entity2
        |> one()
        |> Stage.normalize()

      assert compute(entries, Module37, %{}, %{}, %{}, query_opts(run_query)) == %{first: term}
    end

    test "raises on a count where a set is declared" do
      entries = [entry(:rows, [Entity2], [], fn -> count(Entity2) end)]

      expected_msg =
        "derived field :rows in Hologram.Test.Fixtures.Component.Module37 is declared [Hologram.Test.Fixtures.Entity.Module2], but its query is a count of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute(entries, Module37, %{}, %{}, %{}, query_opts(&no_query/3))
      end
    end

    test "raises on one row where a count is declared" do
      entries = [entry(:total, :integer, [], fn -> one(Entity2) end)]

      expected_msg =
        "derived field :total in Hologram.Test.Fixtures.Component.Module37 is declared :integer, but its query is one Hologram.Test.Fixtures.Entity.Module2 row"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute(entries, Module37, %{}, %{}, %{}, query_opts(&no_query/3))
      end
    end

    test "takes a value of each type with a test of its own" do
      entries = [
        entry(:atom, :atom, [], fn -> :a end),
        entry(:boolean, :boolean, [], fn -> true end),
        entry(:integer, :integer, [], fn -> 1 end),
        entry(:list, :list, [], fn -> [1] end),
        entry(:map, :map, [], fn -> %{a: 1} end),
        entry(:row, Entity2, [], fn -> Entity2.new(id: "a") end),
        entry(:string, :string, [], fn -> "a" end)
      ]

      assert compute_plain(entries, %{}) == %{
               atom: :a,
               boolean: true,
               integer: 1,
               list: [1],
               map: %{a: 1},
               row: Entity2.new(id: "a"),
               string: "a"
             }
    end

    test "raises on a value that is no row of the entity type declared" do
      entries = [entry(:row, Entity2, [], fn -> %{id: "a"} end)]

      expected_msg =
        ~s/derived field :row in Hologram.Test.Fixtures.Component.Module37 is declared Hologram.Test.Fixtures.Entity.Module2, but computed %{id: "a"}/

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "takes anything for a module type that is no entity type" do
      entries = [entry(:value, Module37, [], fn -> 1 end)]

      assert compute_plain(entries, %{}) == %{value: 1}
    end

    test "takes anything for a list type of what is no entity type" do
      entries = [entry(:tags, [:string], [], fn -> ["a", 1] end)]

      assert compute_plain(entries, %{}) == %{tags: ["a", 1]}
    end

    test "raises on a query result of a field the build didn't register as a query" do
      entries = [entry(:entities, [Entity2], [], fn -> filter(Entity2, a == true) end)]

      expected_msg =
        "derived field :entities in Hologram.Test.Fixtures.Component.Module37 returned a query the build didn't register - a query is built in the derived field's own function or the builders it calls, not passed in as data"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "takes nil for any type" do
      assert compute_plain([entry(:label, :string, [], fn -> nil end)], %{}) == %{label: nil}
    end

    test "takes an integer for a float" do
      assert compute_plain([entry(:ratio, :float, [], fn -> 1 end)], %{}) == %{ratio: 1}
    end

    test "takes a list of rows of the entity type a set is declared with" do
      row = Entity2.new(id: "a")

      assert compute_plain([entry(:rows, [Entity2], [], fn -> [row] end)], %{}) == %{rows: [row]}
    end

    test "takes anything for a type with no test of its own" do
      assert compute_plain([entry(:value, :any, [], fn -> {1, 2} end)], %{}) == %{value: {1, 2}}
    end

    test "raises on a value of another type" do
      entries = [entry(:label, :string, [], fn -> 3 end)]

      expected_msg =
        "derived field :label in Hologram.Test.Fixtures.Component.Module37 is declared :string, but computed 3"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "raises on a set holding a row of another entity type" do
      entries = [entry(:rows, [Entity2], [], fn -> [%{id: "a"}] end)]

      expected_msg =
        ~s/derived field :rows in Hologram.Test.Fixtures.Component.Module37 is declared [Hologram.Test.Fixtures.Entity.Module2], but computed [%{id: "a"}]/

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "raises on a prop that is not set" do
      entries = [entry(:double, :integer, [:count], &(&1 * 2))]

      expected_msg =
        "derived field :double in Hologram.Test.Fixtures.Component.Module37 reads :count, which is not set - give it a default or pass it"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "raises on a prop from a context that doesn't hold it" do
      entries = [entry(:label, :string, [:theme], & &1)]

      expected_msg =
        "derived field :label in Hologram.Test.Fixtures.Component.Module37 reads :theme, which is not set - the context has no such key"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "raises on a state entry that is not set" do
      entries = [entry(:double, :integer, [:step], &(&1 * 2), true)]

      expected_msg =
        "derived field :double in Hologram.Test.Fixtures.Component.Module37 reads :step, which is not set - give it a default or set it in init/3"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute_plain(entries, %{})
      end
    end

    test "raises on a param of a page that is not set" do
      entries = [entry(:label, :string, [:project_id], &to_string/1)]

      expected_msg =
        "derived field :label in Hologram.Test.Fixtures.Page.Module17 reads :project_id, which is not set - pass it as a param of the page"

      assert_error Hologram.MisuseError, expected_msg, fn ->
        compute(entries, Module17, %{}, %{}, %{}, plain_opts())
      end
    end

    test "raises on state read by a component rendered without a cid" do
      entries = [entry(:double, :integer, [:step], &(&1 * 2), true)]

      expected_msg =
        "derived field :double in Hologram.Test.Fixtures.Component.Module37 reads state :step, which a component rendered without a cid doesn't have - give it a cid"

      assert_error Hologram.StateError, expected_msg, fn ->
        compute(entries, Module37, %{}, %{step: 1}, %{}, [{:stateless, true} | plain_opts()])
      end
    end
  end

  describe "not_computed/1" do
    test "returns a placeholder for each field" do
      entries = [entry(:double, :integer, [:step], &(&1 * 2), true)]

      assert not_computed(entries) == %{double: %NotComputed{field: :double}}
    end
  end

  describe "split_by_init/1" do
    test "splits the fields reading only props from the ones reading state" do
      props_only = entry(:double, :integer, [:count], &(&1 * 2))
      state_reading = entry(:total, :integer, [:step], & &1, true)

      assert split_by_init([state_reading, props_only]) == {[props_only], [state_reading]}
    end
  end

  describe "validate_state_computed!/3" do
    test "accepts state holding no placeholder" do
      assert validate_state_computed!(%{step: 1}, Module37, "init/3") == :ok
    end

    test "names the smallest field of an entry holding several placeholders" do
      state = %{copy: %{a: %NotComputed{field: :triple}, b: %NotComputed{field: :double}}}

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "names the smallest key of state holding several nested placeholders" do
      state = %{
        copy_a: [%NotComputed{field: :triple}],
        copy_b: %{summary: %NotComputed{field: :double}}
      }

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :triple in state :copy_a before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "names the smallest key of state holding several placeholders" do
      state = %{
        copy_b: %NotComputed{field: :double},
        copy_a: %NotComputed{field: :triple}
      }

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :triple in state :copy_a before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "raises on state holding a placeholder" do
      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(%{copy: %NotComputed{field: :double}}, Module37, "init/3")
      end
    end

    test "raises on state holding a placeholder in an improper list's tail" do
      state = %{copy: [1 | %NotComputed{field: :double}]}

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "raises on state holding a placeholder inside a list" do
      state = %{copy: [1, %NotComputed{field: :double}]}

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "raises on state holding a placeholder inside a map" do
      state = %{copy: %{summary: %NotComputed{field: :double}}}

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end

    test "raises on state holding a placeholder inside a tuple" do
      state = %{copy: {:ok, %NotComputed{field: :double}}}

      expected_msg =
        "init/3 of Hologram.Test.Fixtures.Component.Module37 stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init"

      assert_error Hologram.StateError, expected_msg, fn ->
        validate_state_computed!(state, Module37, "init/3")
      end
    end
  end
end
