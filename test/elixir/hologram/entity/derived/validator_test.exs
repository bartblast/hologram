defmodule Hologram.Entity.Derived.ValidatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Derived.Validator

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module35

  defp validate(entity_types) do
    definitions =
      for entity_type <- entity_types,
          {name, _type, _opts} <- entity_type.__derived__(),
          into: %{},
          do: {{entity_type, name}, Derived.resolve(entity_type, name)}

    validate_model!(entity_types, definitions)
  end

  describe "validate_model!/2" do
    test "returns :ok for definitions computing what their fields declare" do
      assert validate([Module32, Module33, Module34, Module35]) == :ok
    end

    test "returns :ok for an integer a float field reads" do
      defmodule Fixture1 do
        use Hologram.Entity

        attribute :position, :integer

        derived :ratio, :float, fn position -> position end
      end

      assert validate([Fixture1]) == :ok
    end

    test "raises on a count declared as a set" do
      line = __ENV__.line + 9

      defmodule Fixture2 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        derived :recent, [Module33], fn messages -> count(messages) end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :recent in Hologram.Entity.Derived.ValidatorTest.Fixture2 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is a count (:integer)\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture2]) end
    end

    test "raises on strings joined declared as an integer" do
      line = __ENV__.line + 7

      defmodule Fixture3 do
        use Hologram.Entity

        attribute :name, :string

        derived :label, :integer, fn name -> name <> "!" end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture3 is declared :integer, but its definition is a string (<>)\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture3]) end
    end

    test "raises on an enum read where an enum with other values is declared" do
      line = __ENV__.line + 9

      defmodule Fixture4 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :message, Module33

        derived :level, :enum, [values: [:low, :mid, :high]], fn message -> message.tier end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :level in Hologram.Entity.Derived.ValidatorTest.Fixture4 is declared :enum with values [:low, :mid, :high], but its definition is message.tier, a :enum with values [:low, :high]\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture4]) end
    end

    test "raises on a branch of an if computing another type" do
      line = __ENV__.line + 7

      defmodule Fixture5 do
        use Hologram.Entity

        attribute :position, :integer

        derived :rank, :integer, fn position -> if position > 1, do: 1, else: "many" end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :rank in Hologram.Entity.Derived.ValidatorTest.Fixture5 is declared :integer, but a branch of its definition is the value "many"\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture5]) end
    end

    test "raises on an operand of <> computing another type" do
      line = __ENV__.line + 8

      defmodule Fixture6 do
        use Hologram.Entity

        attribute :name, :string
        attribute :position, :integer

        derived :label, :string, fn name, position -> name <> position end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture6 is declared :string, but an operand of its <> is position, a :integer\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture6]) end
    end

    test "raises on a row of what is no entity type" do
      line = __ENV__.line + 5

      defmodule Fixture7 do
        use Hologram.Entity

        derived :item, Hologram.Query, fn -> nil end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :item in Hologram.Entity.Derived.ValidatorTest.Fixture7 is declared Hologram.Query, but Hologram.Query is not an entity type
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :item in Hologram.Entity.Derived.ValidatorTest.Fixture7 is declared Hologram.Query, but its definition is the value nil - a field holding rows is defined by a query over the row's sets\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture7]) end
    end

    test "raises on a server-only attribute read" do
      line = __ENV__.line + 7

      defmodule Fixture8 do
        use Hologram.Entity

        attribute :secret, :string, server_only: true

        derived :shout, :string, fn secret -> secret <> "!" end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :shout in Hologram.Entity.Derived.ValidatorTest.Fixture8 reads Hologram.Entity.Derived.ValidatorTest.Fixture8.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture8]) end
    end

    test "raises on a cycle on one entity type, naming every field" do
      line = __ENV__.line + 7

      defmodule Fixture9 do
        use Hologram.Entity

        attribute :position, :integer

        derived :first, :integer, fn second -> second end

        derived :second, :integer, fn first -> first end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture9.first, Hologram.Entity.Derived.ValidatorTest.Fixture9.second\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture9]) end
    end

    test "raises on a cycle through two entity types, naming every field" do
      line = __ENV__.line + 7

      defmodule Fixture10 do
        use Hologram.Entity

        relationship :children, [Hologram.Entity.Derived.ValidatorTest.Fixture11], inverse: parent

        derived :busy_count, :integer, fn children ->
          children
          |> filter(busy == true)
          |> count()
        end
      end

      defmodule Fixture11 do
        use Hologram.Entity

        relationship :parent, Hologram.Entity.Derived.ValidatorTest.Fixture10

        derived :busy, :boolean, fn parent -> parent.busy_count > 0 end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture10.busy_count, Hologram.Entity.Derived.ValidatorTest.Fixture11.busy\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture10, Fixture11]) end
    end

    test "raises on a field reading itself through a related row" do
      line = __ENV__.line + 7

      defmodule Fixture12 do
        use Hologram.Entity

        relationship :parent, Hologram.Entity.Derived.ValidatorTest.Fixture12, optional: true

        derived :depth, :integer, fn parent -> parent.depth end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :depth in Hologram.Entity.Derived.ValidatorTest.Fixture12 reads itself through a related row\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture12]) end
    end

    test "raises on fields reading each other in several cycles, naming every one" do
      line = __ENV__.line + 7

      defmodule Fixture13 do
        use Hologram.Entity

        attribute :position, :integer

        derived :a, :integer, fn b, c -> if b > 1, do: c, else: 0 end

        derived :b, :integer, fn a -> a end

        derived :c, :integer, fn a -> a end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture13.a, Hologram.Entity.Derived.ValidatorTest.Fixture13.b, Hologram.Entity.Derived.ValidatorTest.Fixture13.c\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture13]) end
    end

    test "raises on a server-only attribute read through a path" do
      line = __ENV__.line + 13

      defmodule Fixture14Owner do
        use Hologram.Entity

        attribute :secret, :string, server_only: true
      end

      defmodule Fixture14 do
        use Hologram.Entity

        relationship :owner, Fixture14Owner

        derived :leak, :string, fn owner -> owner.secret end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :leak in Hologram.Entity.Derived.ValidatorTest.Fixture14 reads Hologram.Entity.Derived.ValidatorTest.Fixture14Owner.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture14Owner, Fixture14])
      end
    end

    test "raises on a server-only attribute of the row a query's condition reads" do
      line = __ENV__.line + 11

      defmodule Fixture15 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        attribute :secret, :string, server_only: true

        relationship :messages, [Module33]

        derived :matching, :integer, fn messages, secret ->
          messages
          |> filter(body == ^secret)
          |> count()
        end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :matching in Hologram.Entity.Derived.ValidatorTest.Fixture15 reads Hologram.Entity.Derived.ValidatorTest.Fixture15.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture15]) end
    end

    test "raises on a server-only attribute of the related rows a query sorts by" do
      line = __ENV__.line + 15

      defmodule Fixture16Message do
        use Hologram.Entity

        attribute :secret, :string, server_only: true

        relationship :channel, Hologram.Entity.Derived.ValidatorTest.Fixture16
      end

      defmodule Fixture16 do
        use Hologram.Entity

        relationship :messages, [Fixture16Message], inverse: channel

        derived :sorted, [Fixture16Message], fn messages -> sort(messages, secret) end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :sorted in Hologram.Entity.Derived.ValidatorTest.Fixture16 reads Hologram.Entity.Derived.ValidatorTest.Fixture16Message.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture16Message, Fixture16])
      end
    end

    test "raises on a cycle through an include and a set a source ends at" do
      line = __ENV__.line + 15

      defmodule Fixture17Child do
        use Hologram.Entity

        relationship :parent, Hologram.Entity.Derived.ValidatorTest.Fixture17

        derived :sibling_count, :integer, fn parent -> count(parent.with_counts) end
      end

      defmodule Fixture17 do
        use Hologram.Entity

        relationship :children, [Fixture17Child], inverse: parent

        derived :with_counts, [Fixture17Child], fn children ->
          include(children, sibling_count)
        end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture17.with_counts, Hologram.Entity.Derived.ValidatorTest.Fixture17Child.sibling_count\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture17Child, Fixture17])
      end
    end

    test "raises on every violation, in the order of the fields" do
      line = __ENV__.line + 7

      defmodule Fixture18 do
        use Hologram.Entity

        attribute :name, :string

        derived :b, :integer, fn name -> name end

        derived :a, :integer, fn name -> name <> "!" end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line + 2}: derived field :a in Hologram.Entity.Derived.ValidatorTest.Fixture18 is declared :integer, but its definition is a string (<>)
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :b in Hologram.Entity.Derived.ValidatorTest.Fixture18 is declared :integer, but its definition is name, a :string\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture18]) end
    end

    test "raises on an enum value the field does not declare" do
      line = __ENV__.line + 5

      defmodule Fixture19 do
        use Hologram.Entity

        derived :tier, :enum, [values: [:low, :high]], fn -> :mid end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :tier in Hologram.Entity.Derived.ValidatorTest.Fixture19 is declared :enum with values [:low, :high], but its definition is the value :mid\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture19]) end
    end

    test "raises on one row declared as a set" do
      line = __ENV__.line + 9

      defmodule Fixture20 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        derived :first, [Module33], fn messages -> one(messages) end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :first in Hologram.Entity.Derived.ValidatorTest.Fixture20 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is one Hologram.Test.Fixtures.Entity.Module33 row\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture20]) end
    end

    test "raises on a set defined by what is no query" do
      line = __ENV__.line + 7

      defmodule Fixture21 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        derived :none, [Module33], fn -> nil end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :none in Hologram.Entity.Derived.ValidatorTest.Fixture21 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is the value nil - a field holding rows is defined by a query over the row's sets\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture21]) end
    end

    test "raises on a set defined by a choice between queries" do
      line = __ENV__.line + 11

      defmodule Fixture23 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        attribute :name, :string

        relationship :messages, [Module33]

        derived :picked, [Module33], fn messages, name ->
          if name == "x", do: take(messages, 1), else: messages
        end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :picked in Hologram.Entity.Derived.ValidatorTest.Fixture23 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is a choice between values (if) - a field holding rows is defined by a query over the row's sets\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture23]) end
    end

    test "raises on a branch of an if joined by <> computing another type" do
      line = __ENV__.line + 8

      defmodule Fixture22 do
        use Hologram.Entity

        attribute :name, :string
        attribute :position, :integer

        derived :label, :string, fn name, position ->
          name <> if(position > 1, do: "a", else: 5)
        end
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture22 is declared :string, but an operand of its <> is the value 5\
      """

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture22]) end
    end
  end
end
