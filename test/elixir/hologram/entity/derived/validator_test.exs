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

    test "raises on a derived set an allow rule reads when it depends on a sequence number" do
      line = __ENV__.line + 15

      defmodule Fixture200 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture201 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture200]

        derived :fresh, [Hologram.Entity.Derived.ValidatorTest.Fixture200], fn messages ->
          filter(messages, server_updated_seq > 5)
        end

        allow :read, when: any(message <- fresh, message.public == true)
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :fresh in Hologram.Entity.Derived.ValidatorTest.Fixture201 reads Hologram.Entity.Derived.ValidatorTest.Fixture200.server_updated_seq, a sequence number, and an allow rule of Hologram.Entity.Derived.ValidatorTest.Fixture201 reads the field. A browser and the server read a sequence number differently until it's final, so no rule can depend on it\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture200, Fixture201])
      end
    end

    test "returns :ok for a rule reading a set a declared sort orders by a sequence number" do
      defmodule Fixture203 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture204 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture203],
          sort: server_created_seq

        derived :open, [Hologram.Entity.Derived.ValidatorTest.Fixture203], fn messages ->
          filter(messages, public == true)
        end

        allow :read, when: any(message <- open, message.public == true)
      end

      assert validate([Fixture203, Fixture204]) == :ok
    end

    test "returns :ok for a rule reading a set sorted by a sequence number with no bound" do
      defmodule Fixture205 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture206 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture205]

        derived :ordered, [Hologram.Entity.Derived.ValidatorTest.Fixture205], fn messages ->
          sort(messages, server_created_seq)
        end

        allow :read, when: any(message <- ordered, message.public == true)
      end

      assert validate([Fixture205, Fixture206]) == :ok
    end

    test "raises on a rule reading a set a take bounds over a sort by a sequence number" do
      line = __ENV__.line + 15

      defmodule Fixture207 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture208 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture207]

        derived :newest, [Hologram.Entity.Derived.ValidatorTest.Fixture207], fn messages ->
          messages
          |> sort(server_updated_seq: :desc)
          |> take(1)
        end

        allow :read, when: any(message <- newest, message.public == true)
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :newest in Hologram.Entity.Derived.ValidatorTest.Fixture208 reads Hologram.Entity.Derived.ValidatorTest.Fixture207.server_updated_seq, a sequence number, and an allow rule of Hologram.Entity.Derived.ValidatorTest.Fixture208 reads the field. A browser and the server read a sequence number differently until it's final, so no rule can depend on it\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture207, Fixture208])
      end
    end

    test "returns :ok for a take over a derived set, which orders by its own sort keys" do
      defmodule Fixture209 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture210 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture209]

        derived :ordered, [Hologram.Entity.Derived.ValidatorTest.Fixture209], fn messages ->
          sort(messages, server_updated_seq)
        end

        derived :first_one, [Hologram.Entity.Derived.ValidatorTest.Fixture209], fn ordered ->
          take(ordered, 1)
        end

        allow :read, when: any(message <- first_one, message.public == true)
      end

      assert validate([Fixture209, Fixture210]) == :ok

      {:query, term} = Derived.resolve(Fixture210, :first_one)

      assert term.sort == [id: :asc]
    end

    test "walks derived fields sharing what they read once each" do
      levels =
        Enum.map_join(1..30, "\n", fn level ->
          previous = "f#{level - 1}"

          "derived :f#{level}, :boolean, fn #{previous} -> #{previous} == true or #{previous} == false end"
        end)

      [{module, _bytecode}] =
        Code.compile_string("""
        defmodule Hologram.Entity.Derived.ValidatorTest.Fixture211 do
          use Hologram.Entity

          attribute :f0, :boolean

          #{levels}

          allow :read, when: f30 == true
        end
        """)

      assert validate([module]) == :ok
    end

    test "raises on a derived field holding a value that an allow rule reads" do
      line = __ENV__.line + 5

      defmodule Fixture212 do
        use Hologram.Entity

        derived :numbered, :integer, fn server_updated_seq -> server_updated_seq end

        allow :read, when: numbered > 5
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :numbered in Hologram.Entity.Derived.ValidatorTest.Fixture212 reads Hologram.Entity.Derived.ValidatorTest.Fixture212.server_updated_seq, a sequence number, and an allow rule of Hologram.Entity.Derived.ValidatorTest.Fixture212 reads the field. A browser and the server read a sequence number differently until it's final, so no rule can depend on it\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture212])
      end
    end

    test "raises on a derived field an update rule reads on the row after the change" do
      line = __ENV__.line + 5

      defmodule Fixture217 do
        use Hologram.Entity

        derived :numbered, :integer, fn server_updated_seq -> server_updated_seq end

        allow :update, when: new(numbered) > 5
      end

      expected_msg = """
      invalid data model:
        * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :numbered in Hologram.Entity.Derived.ValidatorTest.Fixture217 reads Hologram.Entity.Derived.ValidatorTest.Fixture217.server_updated_seq, a sequence number, and an allow rule of Hologram.Entity.Derived.ValidatorTest.Fixture217 reads the field. A browser and the server read a sequence number differently until it's final, so no rule can depend on it\
      """

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate([Fixture217])
      end
    end

    test "returns :ok for an update rule reading a plain field on the row after the change" do
      defmodule Fixture218 do
        use Hologram.Entity

        attribute :status, :string

        derived :shout, :string, fn status -> status end

        allow :update, when: status == "a" and new(shout) == "b"
      end

      assert validate([Fixture218]) == :ok
    end

    test "returns :ok for a bounded sort a unique id decides before a sequence number" do
      defmodule Fixture213 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture214 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture213]

        derived :first_by_id, [Hologram.Entity.Derived.ValidatorTest.Fixture213], fn messages ->
          messages
          |> sort(id: :asc, server_created_seq: :desc)
          |> take(1)
        end

        allow :read, when: any(message <- first_by_id, message.public == true)
      end

      assert validate([Fixture213, Fixture214]) == :ok
    end

    test "returns :ok for a sort by a sequence number under a skip of nothing" do
      defmodule Fixture215 do
        use Hologram.Entity

        attribute :public, :boolean, default: false

        allow :read
      end

      defmodule Fixture216 do
        use Hologram.Entity

        relationship :messages, [Hologram.Entity.Derived.ValidatorTest.Fixture215]

        derived :all_rows, [Hologram.Entity.Derived.ValidatorTest.Fixture215], fn messages ->
          messages
          |> sort(server_created_seq)
          |> skip(0)
        end

        allow :read, when: any(message <- all_rows, message.public == true)
      end

      assert validate([Fixture215, Fixture216]) == :ok
    end

    test "returns :ok for a derived field reading a sequence number that no rule reads" do
      defmodule Fixture202 do
        use Hologram.Entity

        derived :numbered, :integer, fn server_created_seq -> server_created_seq end

        allow :read
      end

      assert validate([Fixture202]) == :ok
    end

    test "raises on a count declared as a set" do
      line = __ENV__.line + 9

      defmodule Fixture2 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        relationship :messages, [Module33]

        derived :recent, [Module33], fn messages -> count(messages) end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :recent in Hologram.Entity.Derived.ValidatorTest.Fixture2 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is a count (:integer)\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture2]) end
    end

    test "raises on strings joined declared as an integer" do
      line = __ENV__.line + 7

      defmodule Fixture3 do
        use Hologram.Entity

        attribute :name, :string

        derived :label, :integer, fn name -> name <> "!" end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture3 is declared :integer, but its definition is a string (<>)\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :level in Hologram.Entity.Derived.ValidatorTest.Fixture4 is declared :enum with values [:low, :mid, :high], but its definition is message.tier, a :enum with values [:low, :high]\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture4]) end
    end

    test "raises on a branch of an if computing another type" do
      line = __ENV__.line + 7

      defmodule Fixture5 do
        use Hologram.Entity

        attribute :position, :integer

        derived :rank, :integer, fn position -> if position > 1, do: 1, else: "many" end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :rank in Hologram.Entity.Derived.ValidatorTest.Fixture5 is declared :integer, but a branch of its definition is the value "many"\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture5]) end
    end

    test "returns :ok for an integer at either end of 64 bits" do
      defmodule Fixture25 do
        use Hologram.Entity

        derived :highest, :integer, fn -> 9_223_372_036_854_775_807 end

        derived :lowest, :integer, fn -> -9_223_372_036_854_775_808 end
      end

      assert validate([Fixture25]) == :ok
    end

    test "returns :ok for an integer past 64 bits a float field holds" do
      defmodule Fixture26 do
        use Hologram.Entity

        derived :cap, :float, fn -> 9_223_372_036_854_775_808 end
      end

      assert validate([Fixture26]) == :ok
    end

    test "returns :ok for an integer at either end of what a float holds" do
      defmodule Fixture30 do
        use Hologram.Entity

        @highest 2 ** 1024 - 2 ** 970 - 1
        @lowest -@highest

        derived :highest, :float, fn -> @highest end

        derived :lowest, :float, fn -> @lowest end
      end

      assert validate([Fixture30]) == :ok
    end

    test "raises on an integer above what a float holds" do
      line = __ENV__.line + 7

      defmodule Fixture31 do
        use Hologram.Entity

        @huge 2 ** 1024 - 2 ** 970

        derived :cap, :float, fn -> @huge end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :cap in Hologram.Entity.Derived.ValidatorTest.Fixture31 is declared :float, but its definition is the value #{2 ** 1024 - 2 ** 970}, which doesn't fit in a float\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture31]) end
    end

    test "raises on an integer below what a float holds" do
      line = __ENV__.line + 7

      defmodule Fixture32 do
        use Hologram.Entity

        @huge -(2 ** 1024 - 2 ** 970)

        derived :floor, :float, fn -> @huge end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :floor in Hologram.Entity.Derived.ValidatorTest.Fixture32 is declared :float, but its definition is the value #{-(2 ** 1024 - 2 ** 970)}, which doesn't fit in a float\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture32]) end
    end

    test "raises on a branch of an if holding an integer too large for a float" do
      line = __ENV__.line + 9

      defmodule Fixture33 do
        use Hologram.Entity

        @huge 2 ** 1024 - 2 ** 970

        attribute :position, :integer

        derived :cap, :float, fn position -> if position > 1, do: 1.5, else: @huge end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :cap in Hologram.Entity.Derived.ValidatorTest.Fixture33 is declared :float, but a branch of its definition is the value #{2 ** 1024 - 2 ** 970}, which doesn't fit in a float\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture33]) end
    end

    test "raises on an integer above 64 bits" do
      line = __ENV__.line + 5

      defmodule Fixture27 do
        use Hologram.Entity

        derived :cap, :integer, fn -> 9_223_372_036_854_775_808 end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :cap in Hologram.Entity.Derived.ValidatorTest.Fixture27 is declared :integer, but its definition is the value 9223372036854775808, which doesn't fit in 64 bits\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture27]) end
    end

    test "raises on an integer below 64 bits" do
      line = __ENV__.line + 5

      defmodule Fixture28 do
        use Hologram.Entity

        derived :floor, :integer, fn -> -9_223_372_036_854_775_809 end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :floor in Hologram.Entity.Derived.ValidatorTest.Fixture28 is declared :integer, but its definition is the value -9223372036854775809, which doesn't fit in 64 bits\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture28]) end
    end

    test "raises on a branch of an if holding an integer past 64 bits" do
      line = __ENV__.line + 7

      defmodule Fixture29 do
        use Hologram.Entity

        attribute :position, :integer

        derived :cap, :integer, fn position ->
          if position > 1, do: 1, else: 9_223_372_036_854_775_808
        end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :cap in Hologram.Entity.Derived.ValidatorTest.Fixture29 is declared :integer, but a branch of its definition is the value 9223372036854775808, which doesn't fit in 64 bits\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture29]) end
    end

    test "raises on an operand of <> computing another type" do
      line = __ENV__.line + 8

      defmodule Fixture6 do
        use Hologram.Entity

        attribute :name, :string
        attribute :position, :integer

        derived :label, :string, fn name, position -> name <> position end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture6 is declared :string, but an operand of its <> is position, a :integer\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture6]) end
    end

    test "raises on a row of what is no entity type" do
      line = __ENV__.line + 5

      defmodule Fixture7 do
        use Hologram.Entity

        derived :item, Hologram.Query, fn -> nil end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :item in Hologram.Entity.Derived.ValidatorTest.Fixture7 is declared Hologram.Query, but Hologram.Query is not an entity type\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture7]) end
    end

    test "raises on a server-only attribute read" do
      line = __ENV__.line + 7

      defmodule Fixture8 do
        use Hologram.Entity

        attribute :secret, :string, server_only: true

        derived :shout, :string, fn secret -> secret <> "!" end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :shout in Hologram.Entity.Derived.ValidatorTest.Fixture8 reads Hologram.Entity.Derived.ValidatorTest.Fixture8.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture9.first, Hologram.Entity.Derived.ValidatorTest.Fixture9.second\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture10.busy_count, Hologram.Entity.Derived.ValidatorTest.Fixture11.busy\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture10, Fixture11]) end
    end

    test "raises on a field reading itself through a related row" do
      line = __ENV__.line + 7

      defmodule Fixture12 do
        use Hologram.Entity

        relationship :parent, Hologram.Entity.Derived.ValidatorTest.Fixture12, optional: true

        derived :depth, :integer, fn parent -> parent.depth end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :depth in Hologram.Entity.Derived.ValidatorTest.Fixture12 reads itself through a related row\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture13.a, Hologram.Entity.Derived.ValidatorTest.Fixture13.b, Hologram.Entity.Derived.ValidatorTest.Fixture13.c\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :leak in Hologram.Entity.Derived.ValidatorTest.Fixture14 reads Hologram.Entity.Derived.ValidatorTest.Fixture14Owner.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :matching in Hologram.Entity.Derived.ValidatorTest.Fixture15 reads Hologram.Entity.Derived.ValidatorTest.Fixture15.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :sorted in Hologram.Entity.Derived.ValidatorTest.Fixture16 reads Hologram.Entity.Derived.ValidatorTest.Fixture16Message.secret, which is server_only - a client computes derived fields over the rows it holds, and it never holds that value\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived fields read each other in a cycle: Hologram.Entity.Derived.ValidatorTest.Fixture17.with_counts, Hologram.Entity.Derived.ValidatorTest.Fixture17Child.sibling_count\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line + 2}: derived field :a in Hologram.Entity.Derived.ValidatorTest.Fixture18 is declared :integer, but its definition is a string (<>)
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :b in Hologram.Entity.Derived.ValidatorTest.Fixture18 is declared :integer, but its definition is name, a :string\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture18]) end
    end

    test "raises on an enum value the field does not declare" do
      line = __ENV__.line + 5

      defmodule Fixture19 do
        use Hologram.Entity

        derived :tier, :enum, [values: [:low, :high]], fn -> :mid end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :tier in Hologram.Entity.Derived.ValidatorTest.Fixture19 is declared :enum with values [:low, :high], but its definition is the value :mid\
        """)

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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :first in Hologram.Entity.Derived.ValidatorTest.Fixture20 is declared [Hologram.Test.Fixtures.Entity.Module33], but its definition is one Hologram.Test.Fixtures.Entity.Module33 row\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture20]) end
    end

    test "returns :ok for nil for a set" do
      defmodule Fixture21 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        derived :none, [Module33], fn -> nil end
      end

      assert validate([Fixture21]) == :ok
    end

    test "returns :ok for a set chosen with if between queries and nil" do
      defmodule Fixture23 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        attribute :name, :string

        relationship :messages, [Module33]

        derived :picked, [Module33], fn messages, name ->
          if name == "x", do: take(messages, 1), else: messages
        end

        derived :pinned, [Module33], fn messages, name ->
          if name == "x", do: take(messages, 2)
        end
      end

      assert validate([Fixture23]) == :ok
    end

    test "raises on a branch of a set's if computing another type" do
      line = __ENV__.line + 11

      defmodule Fixture24 do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module33

        attribute :name, :string

        relationship :messages, [Module33]

        derived :picked, [Module33], fn messages, name ->
          if name == "x", do: take(messages, 1), else: count(messages)
        end
      end

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :picked in Hologram.Entity.Derived.ValidatorTest.Fixture24 is declared [Hologram.Test.Fixtures.Entity.Module33], but a branch of its definition is a count (:integer)\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture24]) end
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

      expected_msg =
        normalize_newlines("""
        invalid data model:
          * test/elixir/hologram/entity/derived/validator_test.exs:#{line}: derived field :label in Hologram.Entity.Derived.ValidatorTest.Fixture22 is declared :string, but an operand of its <> is the value 5\
        """)

      assert_error Hologram.CompileError, expected_msg, fn -> validate([Fixture22]) end
    end
  end
end
