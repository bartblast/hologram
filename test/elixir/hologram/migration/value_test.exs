defmodule Hologram.Migration.ValueTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Migration.Value

  defp backfill(expression) do
    body = """
    change_entity MyApp.Trip do
      add_attribute :value, :string, backfill: #{expression}
    end
    """

    [op] =
      "20260813091522"
      |> compile_migration(body)
      |> then(& &1.__hologram_migration__().ops)

    op.opts[:backfill]
  end

  defp refusal(expression) do
    error = assert_raise Hologram.CompileError, fn -> backfill(expression) end

    assert error.line == 5

    error.message
  end

  defp term(expression) do
    assert %Value{term: term} = backfill(expression)

    term
  end

  describe "fills/2" do
    setup do
      pre_model = %{
        entities: %{
          MyApp.Trip => %{
            attributes: [{:destination, :string, []}, {:notes, :string, [optional: true]}],
            relationships: [{:owner, MyApp.User, [optional: true]}],
            roles: [],
            uniques: []
          },
          MyApp.User => %{attributes: [], relationships: [], roles: [], uniques: []}
        },
        roles: %{},
        user_entity: nil
      }

      [pre_model: pre_model]
    end

    test "returns one entry per op carrying a backfill, in op order", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :tier,
          type: :string,
          opts: [backfill: "standard"],
          line: 3
        },
        %{op: :delete_attribute, entity: MyApp.Trip, name: :notes, line: 4},
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :city,
          type: :string,
          opts: [backfill: %Value{term: {:name, [:destination]}}],
          line: 5
        }
      ]

      assert Value.fills(ops, pre_model) == [
               %{
                 backfill: {:constant, "standard"},
                 entity: MyApp.Trip,
                 kind: :attribute,
                 line: 3,
                 member: :tier,
                 nulls_only: false
               },
               %{
                 backfill: {:computed, %{term: {:name, [:destination], :string}, type: :string}},
                 entity: MyApp.Trip,
                 kind: :attribute,
                 line: 5,
                 member: :city,
                 nulls_only: false
               }
             ]
    end

    test "resolves against the model right before the op", %{pre_model: pre_model} do
      ops = [
        %{op: :rename_attribute, entity: MyApp.Trip, from: :destination, to: :place, line: 3},
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :city,
          type: :string,
          opts: [backfill: %Value{term: {:name, [:place]}}],
          line: 4
        }
      ]

      assert [%{backfill: {:computed, %{term: {:name, [:place], :string}}}}] =
               Value.fills(ops, pre_model)
    end

    test "refuses a name a later op adds", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :city,
          type: :string,
          opts: [backfill: %Value{term: {:name, [:later]}}],
          line: 3
        },
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :later,
          type: :string,
          opts: [optional: true],
          line: 4
        }
      ]

      assert_raise Hologram.CompileError, ~r/reads :later/, fn ->
        Value.fills(ops, pre_model)
      end
    end

    test "a tightening fills only the rows holding nil", %{pre_model: pre_model} do
      ops = [
        %{
          op: :change_attribute,
          entity: MyApp.Trip,
          name: :notes,
          changes: [optional: false, backfill: %Value{term: {:name, [:destination]}}],
          line: 3
        }
      ]

      assert [%{kind: :attribute, member: :notes, nulls_only: true}] = Value.fills(ops, pre_model)
    end

    test "reads a relationship's target", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_relationship,
          entity: MyApp.Trip,
          name: :creator,
          type: MyApp.User,
          opts: [optional: true, backfill: %Value{term: {:name, [:owner_id]}}],
          line: 3
        },
        %{
          op: :change_relationship,
          entity: MyApp.Trip,
          name: :owner,
          changes: [optional: false, backfill: "018f0000-0000-7000-8000-000000000000"],
          line: 4
        }
      ]

      assert [
               %{
                 backfill: {:computed, %{type: {:reference, MyApp.User}}},
                 kind: :relationship,
                 member: :creator,
                 nulls_only: false
               },
               %{
                 backfill: {:constant, "018f0000-0000-7000-8000-000000000000"},
                 kind: :relationship,
                 member: :owner,
                 nulls_only: true
               }
             ] = Value.fills(ops, pre_model)
    end

    test "reads relationship options given as a map", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_relationship,
          entity: MyApp.Trip,
          name: :creator,
          type: MyApp.User,
          opts: %{optional: true, backfill: %Value{term: {:name, [:owner_id]}}},
          line: 3
        }
      ]

      assert [%{member: :creator}] = Value.fills(ops, pre_model)
    end

    test "refuses a to-many", %{pre_model: pre_model} do
      ops = [
        %{
          op: :add_relationship,
          entity: MyApp.Trip,
          name: :users,
          type: [MyApp.User],
          opts: [backfill: %Value{term: {:name, [:owner_id]}}],
          line: 3
        }
      ]

      assert_raise Hologram.CompileError, ~r/fills a to-many relationship/, fn ->
        Value.fills(ops, pre_model)
      end
    end

    test "folds across a delete and the cleanup it needs", %{pre_model: pre_model} do
      ops = [
        %{op: :delete_entity, entity: MyApp.User, line: 3},
        %{op: :delete_relationship, entity: MyApp.Trip, name: :owner, line: 4},
        %{
          op: :add_attribute,
          entity: MyApp.Trip,
          name: :city,
          type: :string,
          opts: [backfill: "none"],
          line: 5
        }
      ]

      assert [%{member: :city}] = Value.fills(ops, pre_model)
    end
  end

  describe "normalize_constant/2" do
    test "lowercases a uuid" do
      assert Value.normalize_constant("018F0000-AAAA", :uuid) == "018f0000-aaaa"
    end

    test "holds a datetime in UTC at microsecond precision" do
      assert Value.normalize_constant(~U[2026-01-01 12:00:00Z], :datetime) ==
               ~U[2026-01-01 12:00:00.000000Z]
    end

    test "holds a time at microsecond precision" do
      assert Value.normalize_constant(~T[10:00:00], :time) == ~T[10:00:00.000000]
    end

    test "widens an integer a float holds exactly to a float" do
      assert Value.normalize_constant(3, :float) === 3.0
      assert Value.normalize_constant(9_007_199_254_740_994, :float) === 9_007_199_254_740_994.0
      assert Value.normalize_constant(9_007_199_254_740_993, :float) === 9_007_199_254_740_993
      assert Value.normalize_constant(10 ** 400, :float) === 10 ** 400
    end

    test "leaves a value that isn't of the type for the check to refuse" do
      assert Value.normalize_constant("nope", :datetime) == "nope"
    end

    test "leaves other types alone" do
      assert Value.normalize_constant("A", :string) == "A"
    end
  end

  describe "max_position/0" do
    test "is the largest position at takes" do
      assert Value.max_position() == 1_000_000
    end
  end

  describe "resolve!/4" do
    test "delegates to the resolver" do
      model = %{
        entities: %{
          MyApp.Trip => %{
            attributes: [{:title, :string, []}],
            relationships: [],
            roles: [],
            uniques: []
          }
        },
        roles: %{},
        user_entity: nil
      }

      target = %{kind: :attribute, line: 3, name: :value, opts: [], type: :string}

      assert Value.resolve!(%Value{term: {:name, [:title]}}, model, MyApp.Trip, target) == %{
               term: {:name, [:title], :string},
               type: :string
             }
    end
  end

  describe "validate_ops!/4, a function term" do
    defp function_op(module) do
      value = %Value{args: [:title], term: {:function, module, :__backfill_0__, [:title]}}

      %{
        op: :add_attribute,
        entity: MyApp.Trip,
        name: :value,
        type: :string,
        opts: [backfill: value],
        line: 3
      }
    end

    # The backfill functions a migration generated, as its __after_compile__ gives them.
    defp generated(module, args \\ [:title]), do: [{module, :__backfill_0__, args}]

    test "accepts a function of the migration module" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> String.upcase(title) end
        end
        """)

      assert Value.validate_ops!(
               [function_op(module)],
               "app/migrations/20260813091522.ex",
               module,
               generated(module)
             ) == :ok
    end

    test "refuses a function the module doesn't export at that arity" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn a, b -> a <> b end
        end
        """)

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [function_op(module)],
          "app/migrations/20260813091522.ex",
          module,
          generated(module, [:a, :b])
        )
      end
    end

    test "refuses a function of the migration module the backfill didn't generate" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> String.upcase(title) end
        end
        """)

      op = function_op(module)
      value = %Value{args: [:status], term: {:function, module, :module_info, [:status]}}

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [%{op | opts: [backfill: value]}],
          "app/migrations/20260813091522.ex",
          module,
          generated(module)
        )
      end
    end

    test "refuses a listed function the module doesn't export at that arity" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> String.upcase(title) end
        end
        """)

      op = function_op(module)
      value = %Value{args: [:a, :b], term: {:function, module, :__backfill_0__, [:a, :b]}}

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [%{op | opts: [backfill: value]}],
          "app/migrations/20260813091522.ex",
          module,
          generated(module, [:a, :b])
        )
      end
    end

    test "refuses a function of the migration module taking no arguments" do
      module =
        compile_migration("20260813091522", """
        def __backfill_0__, do: "x"

        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: "x"
        end
        """)

      value = %Value{args: [], term: {:function, module, :__backfill_0__, []}}
      op = %{function_op(module) | opts: [backfill: value]}

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [op],
          "app/migrations/20260813091522.ex",
          module,
          generated(module, [])
        )
      end
    end

    test "refuses a function of another migration exporting the same backfill function" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> String.upcase(title) end
      end
      """

      other = compile_migration("20260813091522", body)
      owner = compile_migration("20260813091523", body)

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [function_op(other)],
          "app/migrations/20260813091523.ex",
          owner,
          generated(owner)
        )
      end

      assert Value.validate_ops!(
               [function_op(owner)],
               "app/migrations/20260813091523.ex",
               owner,
               generated(owner)
             ) == :ok
    end

    test "refuses a function term whose arguments differ from the value's" do
      module =
        compile_migration("20260813091522", """
        def __backfill_0__(id), do: id

        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: "x"
        end
        """)

      op = function_op(module)
      value = %Value{args: [:title], term: {:function, module, :__backfill_0__, [:id]}}

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!(
          [%{op | opts: [backfill: value]}],
          "app/migrations/20260813091522.ex",
          module,
          generated(module, [:id])
        )
      end
    end

    test "refuses a function nested inside another word" do
      module =
        compile_migration("20260813091522", """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> String.upcase(title) end
        end
        """)

      path = "app/migrations/20260813091522.ex"
      root = function_op(module)
      term = root.opts[:backfill].term

      assert Value.validate_ops!([root], path, module, generated(module)) == :ok

      nested = put_in(root.opts[:backfill].term, {:coalesce, [term, {:value, "a"}]})

      assert_raise Hologram.CompileError, ~r/wasn't written as a backfill expression/, fn ->
        Value.validate_ops!([nested], path, module, generated(module))
      end
    end
  end

  describe "validate_ops!/2" do
    test "passes the terms lowering produces" do
      ops = [
        %{
          op: :add_attribute,
          opts: [backfill: %Value{term: {:coalesce, [{:name, [:a]}, {:value, 1}]}}],
          line: 3
        },
        %{op: :change_attribute, changes: [backfill: %Value{term: {:name, [:a]}}], line: 4},
        %{op: :add_attribute, opts: [backfill: "constant"], line: 5},
        %{op: :delete_attribute, name: :a, line: 6}
      ]

      assert Value.validate_ops!(ops, "app/migrations/20260813091522.ex") == :ok
    end

    test "refuses a term lowering can't produce, in an op's options" do
      value = %Value{term: {:function, File, :rm_rf!, [:title]}}
      ops = [%{op: :add_attribute, opts: [backfill: value], line: 3}]

      error =
        assert_raise Hologram.CompileError, fn ->
          Value.validate_ops!(ops, "app/migrations/20260813091522.ex")
        end

      assert error.line == 3
      assert error.message =~ "wasn't written as a backfill expression"
    end

    test "refuses a term lowering can't produce, in an op's changes" do
      value = %Value{term: {:count, {:function, File, :rm_rf!, []}}}
      ops = [%{op: :change_attribute, changes: [backfill: value], line: 3}]

      assert_raise Hologram.CompileError, fn ->
        Value.validate_ops!(ops, "app/migrations/20260813091522.ex")
      end
    end

    test "refuses a term in options given as a map" do
      value = %Value{term: {:function, File, :rm_rf!, []}}
      ops = [%{op: :add_relationship, opts: %{optional: true, backfill: value}, line: 3}]

      assert_raise Hologram.CompileError, fn ->
        Value.validate_ops!(ops, "app/migrations/20260813091522.ex")
      end
    end

    test "refuses a term under a repeated key" do
      value = %Value{term: {:function, File, :rm_rf!, []}}
      ops = [%{op: :add_attribute, opts: [backfill: "ok", backfill: value], line: 3}]

      assert_raise Hologram.CompileError, fn ->
        Value.validate_ops!(ops, "app/migrations/20260813091522.ex")
      end
    end

    test "passes over options that are an improper list" do
      ops = [%{op: :add_attribute, opts: [{:optional, true} | :tail], line: 3}]

      assert Value.validate_ops!(ops, "app/migrations/20260813091522.ex") == :ok
    end

    for {label, term} <- [
          {"a split no at reads", {:split, {:name, [:a]}, {:value, ","}}},
          {"a split with a column separator",
           {:at, {:split, {:name, [:a]}, {:name, [:sep]}}, {:value, 0}}},
          {"a column position", {:at, {:split, {:name, [:a]}, {:value, ","}}, {:name, [:n]}}},
          {"a coalesce of none", {:coalesce, []}},
          {"a coalesce of one", {:coalesce, [{:name, [:a]}]}},
          {"a join of none", {:concat, []}},
          {"a join of one", {:concat, [{:name, [:a]}]}},
          {"a join left unflattened",
           {:concat, [{:concat, [{:name, [:a]}, {:name, [:b]}]}, {:name, [:c]}]}},
          {"a name with no names", {:name, []}},
          {"a name that is an improper list", {:name, [:a | :b]}}
        ] do
      test "refuses #{label}" do
        ops = [
          %{
            op: :add_attribute,
            opts: [backfill: %Value{term: unquote(Macro.escape(term))}],
            line: 3
          }
        ]

        assert_raise Hologram.CompileError, fn ->
          Value.validate_ops!(ops, "app/migrations/20260813091522.ex")
        end
      end
    end

    test "a migration can't hand-write a term through a pin" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string,
          backfill: ^%{__struct__: Hologram.Migration.Value, term: {:function, File, :rm_rf!, []}}
      end
      """

      error =
        assert_raise Hologram.CompileError, fn ->
          compile_migration("20260813091522", body)
        end

      assert error.message =~ "wasn't written as a backfill expression"
    end
  end

  describe "lower/2, constants" do
    test "keeps a string" do
      assert backfill(~s("standard")) == "standard"
    end

    test "keeps an integer" do
      assert backfill("7") === 7
    end

    test "keeps a float" do
      assert backfill("1.5") == 1.5
    end

    test "keeps a signed number" do
      assert backfill("-7") === -7
    end

    test "keeps a boolean" do
      assert backfill("true") == true
    end

    test "keeps an atom" do
      assert backfill(":draft") == :draft
    end

    test "keeps a module alias" do
      assert backfill("MyApp.Tier") == MyApp.Tier
    end

    test "reads a pinned expression as a constant" do
      assert backfill(~s|^String.upcase("standard")|) == "STANDARD"
    end

    test "resolves an alias in effect inside a pin" do
      body = """
      alias MyApp.Tiers

      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: coalesce(title, ^Tiers.Standard)
      end
      """

      [op] =
        "20260813091522"
        |> compile_migration(body)
        |> then(& &1.__hologram_migration__().ops)

      assert op.opts[:backfill].term ==
               {:coalesce, [{:name, [:title]}, {:value, MyApp.Tiers.Standard}]}
    end

    test "reads a pinned alias headed by an attribute at the op's line" do
      body = """
      @mod String

      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: ^@mod.Tier
      end

      @mod Enum

      def later, do: @mod
      """

      [op] =
        "20260813091522"
        |> compile_migration(body)
        |> then(& &1.__hologram_migration__().ops)

      assert op.opts[:backfill] == String.Tier
    end

    test "resolves an alias headed by __ENV__" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: ^__ENV__.module.Tier
      end
      """

      module = compile_migration("20260813091522", body)
      [op] = module.__hologram_migration__().ops

      assert Atom.to_string(op.opts[:backfill]) == "#{module}.Tier"
    end

    test "reads a pinned sigil as a constant" do
      assert backfill("^~D[2026-01-02]") == ~D[2026-01-02]
    end
  end

  describe "lower/2, names and paths" do
    test "lowers a bare name" do
      assert term("destination") == {:name, [:destination]}
    end

    test "lowers a dot chain" do
      assert term("trip.owner.name") == {:name, [:trip, :owner, :name]}
    end

    test "refuses a dot call with parentheses" do
      assert refusal("trip.owner()") =~ "a backfill expression can't read trip.owner()"
    end

    test "refuses __MODULE__ naming the pin" do
      assert refusal("__MODULE__") =~ "pinned: ^__MODULE__"
    end
  end

  describe "lower/2, <>" do
    test "lowers a join" do
      assert term(~s("Trip to " <> destination)) ==
               {:concat, [{:value, "Trip to "}, {:name, [:destination]}]}
    end

    test "flattens a chain of joins" do
      assert term(~s(first <> " " <> last)) ==
               {:concat, [{:name, [:first]}, {:value, " "}, {:name, [:last]}]}
    end

    test "lowers a pinned operand" do
      assert term(~s|^String.upcase("to ") <> destination|) ==
               {:concat, [{:value, "TO "}, {:name, [:destination]}]}
    end
  end

  describe "lower/2, split and at" do
    test "lowers a part of a split" do
      assert term(~s|at(split(destination, ", "), 0)|) ==
               {:at, {:split, {:name, [:destination]}, {:value, ", "}}, {:value, 0}}
    end

    test "piped and unpiped spellings lower to one term" do
      assert term(~s[destination |> split(", ") |> at(1)]) ==
               term(~s|at(split(destination, ", "), 1)|)
    end

    test "takes a pinned separator" do
      assert term(~s|at(split(destination, ^String.trim(" , ")), 0)|) ==
               {:at, {:split, {:name, [:destination]}, {:value, ","}}, {:value, 0}}
    end

    test "takes a pinned position" do
      assert term(~s|at(split(destination, ","), ^Kernel.+(1, 1))|) ==
               {:at, {:split, {:name, [:destination]}, {:value, ","}}, {:value, 2}}
    end

    test "takes the largest position" do
      assert {:at, _split, {:value, 1_000_000}} = term(~s|at(split(a, ","), 1_000_000)|)
    end

    test "takes negative zero as position 0" do
      assert {:at, _split, {:value, 0}} = term(~s|at(split(a, ","), -0)|)
    end

    test "takes a position with a plus sign" do
      assert {:at, _split, {:value, 1}} = term(~s|at(split(a, ","), +1)|)
    end

    test "refuses split with the wrong arity" do
      assert refusal(~s|at(split(destination), 0)|) ==
               "at reads a part of a split, got: split(destination)"
    end

    test "refuses at with the wrong arity" do
      assert refusal(~s|at(split(destination, ","))|) ==
               ~s|at takes a split and a position, got: at(split(destination, ","))|
    end

    test "refuses a split no at reads" do
      assert refusal(~s|split(destination, ",")|) =~ "a backfill can't store a list"
    end

    test "refuses an empty separator" do
      assert refusal(~s|at(split(destination, ""), 0)|) ==
               ~s(split takes a non-empty separator, got: "")
    end

    test "refuses a separator that is neither a string nor pinned" do
      assert refusal(~s|at(split(destination, sep), 0)|) ==
               "split takes a string separator or a pinned expression, got: sep"
    end

    test "refuses a negative position" do
      assert refusal(~s|at(split(destination, ","), -1)|) ==
               "at counts from 0, got: -1 - it can't count from the end yet"
    end

    test "refuses a position past the largest" do
      assert refusal(~s|at(split(destination, ","), 1_000_001)|) ==
               "at takes a position from 0 to 1000000 or a pinned expression, got: 1_000_001"
    end

    test "refuses a position that is no integer" do
      assert refusal(~s|at(split(destination, ","), n)|) ==
               "at takes a position from 0 to 1000000 or a pinned expression, got: n"
    end

    test "refuses at over anything but a split" do
      assert refusal("at(tags, 0)") == "at reads a part of a split, got: tags"
    end
  end

  describe "lower/2, coalesce" do
    test "lowers its values in order" do
      assert term(~s|coalesce(nickname, first <> last, "none")|) ==
               {:coalesce,
                [
                  {:name, [:nickname]},
                  {:concat, [{:name, [:first]}, {:name, [:last]}]},
                  {:value, "none"}
                ]}
    end

    test "refuses one value" do
      assert refusal("coalesce(nickname)") ==
               "coalesce takes two or more values, got: coalesce(nickname)"
    end

    test "refuses nil among its values" do
      assert refusal("coalesce(nickname, nil)") =~ "a backfill expression can't hold nil"
    end
  end

  describe "lower/2, count" do
    test "lowers a relationship" do
      assert term("count(tags)") == {:count, {:relationship, [:tags]}}
    end

    test "lowers a path to a relationship" do
      assert term("count(trip.tags)") == {:count, {:relationship, [:trip, :tags]}}
    end

    test "piped and unpiped spellings lower to one term" do
      assert term("tags |> count()") == term("count(tags)")
    end

    test "refuses an atom naming the bare spelling" do
      assert refusal("count(:tags)") ==
               "count names the relationship with a bare name, got: :tags - write tags"
    end

    test "refuses anything else" do
      assert refusal(~s|count("tags")|) == ~s(count takes a relationship of the row, got: "tags")
    end

    test "refuses the wrong arity" do
      assert refusal("count(tags, name)") == "count takes a relationship, got: count(tags, name)"
    end

    test "refuses a query from a type naming the fn form" do
      assert refusal("MyApp.Stop |> filter(trip_id == ^1) |> count()") =~
               "for the rows pointing at this one, write a fn naming its id"
    end

    test "refuses a query with stages after the filter naming the fn form" do
      assert refusal("MyApp.Stop |> filter(a == 1) |> sort(a) |> count()") =~
               "for the rows pointing at this one, write a fn naming its id"
    end

    test "refuses an entity type naming the fn form" do
      assert refusal("MyApp.Stop |> count()") =~
               "for the rows pointing at this one, write a fn naming its id"
    end
  end

  describe "lower/2, most_common" do
    test "lowers a set and an attribute" do
      assert term("most_common(tags, name)") ==
               {:most_common, {:relationship, [:tags]}, :name}
    end

    test "piped and unpiped spellings lower to one term" do
      assert term("tags |> most_common(name)") == term("most_common(tags, name)")
    end

    test "refuses an atom attribute naming the bare spelling" do
      assert refusal("most_common(tags, :name)") ==
               "most_common names the attribute with a bare name, got: :name - write name"
    end

    test "refuses an attribute that is no bare name" do
      assert refusal("most_common(tags, trip.name)") ==
               "most_common names the attribute with a bare name, got: trip.name"
    end

    test "refuses a set that is no relationship" do
      assert refusal(~s|most_common("tags", name)|) ==
               ~s(most_common takes a relationship of the row, got: "tags")
    end

    test "refuses the wrong arity" do
      assert refusal("most_common(tags)") ==
               "most_common takes a relationship and an attribute, got: most_common(tags)"
    end
  end

  describe "read_fn/2 and choose_fn!/2, a query body" do
    defp fn_backfill(expression), do: backfill(expression)

    defp compiled_refusal(body) do
      error =
        assert_raise Hologram.CompileError, fn ->
          compile_migration("20260813091522", body)
        end

      error.message
    end

    defp op_with(expression, extra) do
      """
      #{extra}
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: #{expression}
      end
      """
    end

    test "lowers a body whose outermost part is a word, naming its arguments" do
      assert %Value{args: [:title], term: {:coalesce, [{:name, [:title]}, {:value, "x"}]}} =
               fn_backfill(~s|fn title -> coalesce(title, "x") end|)
    end

    test "lowers a piped word body" do
      assert %Value{
               term: {:at, {:split, {:name, [:title]}, {:value, ", "}}, {:value, 0}}
             } = fn_backfill(~s[fn title -> title |> split(", ") |> at(0) end])
    end

    test "lowers a body that's only a field" do
      assert %Value{args: [:title], term: {:name, [:title]}} =
               fn_backfill("fn title -> title end")
    end

    test "lowers a body that's only a path" do
      assert %Value{args: [:trip], term: {:name, [:trip, :currency]}} =
               fn_backfill("fn trip -> trip.currency end")
    end

    test "lowers query(...) to its inner expression" do
      assert %Value{args: [:first, :last], term: {:concat, operands}} =
               fn_backfill(~s|fn first, last -> query(first <> " " <> last) end|)

      assert operands == [{:name, [:first]}, {:value, " "}, {:name, [:last]}]
    end

    test "reads a pinned attribute at the op" do
      body = """
      @fallback "a"
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> coalesce(title, ^@fallback) end
      end
      @fallback "b"
      """

      [op] = compile_migration("20260813091522", body).__hologram_migration__().ops

      assert %Value{term: {:coalesce, [{:name, [:title]}, {:value, "a"}]}} = op.opts[:backfill]
    end

    test "reads the rows pointing at this one, piped and not" do
      for expression <- [
            "fn id -> MyApp.Stop |> filter(trip_id == ^id) |> count() end",
            "fn id -> count(filter(MyApp.Stop, trip_id == ^id)) end"
          ] do
        assert %Value{args: [:id], term: {:count, {:referencing, MyApp.Stop, :trip}}} =
                 fn_backfill(expression)
      end

      for expression <- [
            "fn id -> MyApp.Stop |> filter(trip_id == ^id) |> most_common(currency) end",
            "fn id -> most_common(filter(MyApp.Stop, trip_id == ^id), currency) end"
          ] do
        assert %Value{term: {:most_common, {:referencing, MyApp.Stop, :trip}, :currency}} =
                 fn_backfill(expression)
      end
    end

    test "expands the alias of the queried type where the op is written" do
      body = """
      alias MyApp.Stop
      change_entity MyApp.Trip do
        add_attribute :value, :integer, backfill: fn id -> Stop |> filter(trip_id == ^id) |> count() end
      end
      """

      [op] = compile_migration("20260813091522", body).__hologram_migration__().ops

      assert %Value{term: {:count, {:referencing, MyApp.Stop, :trip}}} = op.opts[:backfill]
    end

    test "refuses a query with another condition" do
      for condition <- ["trip_id != ^id", "name == ^id", "trip_id == ^other", "trip_id == 1"] do
        assert refusal("fn id -> MyApp.Stop |> filter(#{condition}) |> count() end") =~
                 "a backfill fn queries the rows pointing at this one"
      end
    end

    test "refuses a query pinning id when id isn't an argument" do
      assert refusal("fn title -> MyApp.Stop |> filter(trip_id == ^id) |> count() end") =~
               "with id among the fn's arguments"
    end

    test "refuses a query that doesn't end in a word" do
      assert refusal("fn id -> MyApp.Stop |> filter(trip_id == ^id) end") =~
               "a query in a backfill ends in count or most_common"
    end

    test "refuses a body that's only a constant, naming the constant form" do
      for expression <- [~s(fn title -> "x" end), "fn title -> 1 end", "fn title -> ^title end"] do
        assert refusal(expression) =~ "for one value for every row, write it without the fn"
      end
    end

    test "refuses a body that's only a module attribute, naming the constant form" do
      assert refusal("fn title -> @fallback end") =~ "like backfill: ^@default"
    end

    test "refuses query(...) holding only a constant" do
      assert refusal(~s|fn title -> query("x") end|) =~ "write it without the fn"
    end

    test "accepts a function inside a pin binding an argument's name" do
      module =
        compile_migration(
          "20260813091522",
          op_with(
            ~s|fn title -> coalesce(title, ^Enum.map_join(["F"], fn title -> title end)) end|,
            ""
          )
        )

      assert [
               %{
                 opts: [
                   backfill: %Value{
                     args: [:title],
                     term: {:coalesce, [{:name, [:title]}, {:value, "F"}]}
                   }
                 ]
               }
             ] =
               module.__hologram_migration__().ops
    end

    test "accepts a match? inside a pin binding an argument's name" do
      body =
        ~S|fn title -> coalesce(title, ^to_string(match?({title, _} when is_binary(title), {"a", 1}))) end|

      module = compile_migration("20260813091522", op_with(body, ""))

      assert [
               %{
                 opts: [
                   backfill: %Value{term: {:coalesce, [{:name, [:title]}, {:value, "true"}]}}
                 ]
               }
             ] =
               module.__hologram_migration__().ops
    end

    test "accepts a bitstring generator inside a pin binding an argument's name" do
      body =
        ~S|fn title -> coalesce(title, ^(for <<title, _rest <- "ab">>, into: "", do: <<title>>)) end|

      module = compile_migration("20260813091522", op_with(body, ""))

      assert [%{opts: [backfill: %Value{term: {:coalesce, [{:name, [:title]}, {:value, "a"}]}}]}] =
               module.__hologram_migration__().ops
    end

    test "accepts Kernel.match? inside a pin binding an argument's name" do
      body =
        ~S|fn title -> coalesce(title, ^to_string(Kernel.match?({title, _} when is_binary(title), {"a", 1}))) end|

      module = compile_migration("20260813091522", op_with(body, ""))

      assert [
               %{
                 opts: [
                   backfill: %Value{term: {:coalesce, [{:name, [:title]}, {:value, "true"}]}}
                 ]
               }
             ] =
               module.__hologram_migration__().ops
    end

    test "accepts a capture inside a pin named like an argument" do
      body = ~S|fn title -> coalesce(title, ^Enum.map_join(["F"], &title/1)) end|

      module = compile_migration("20260813091522", op_with(body, "def title(x), do: x"))

      assert [%{opts: [backfill: %Value{term: {:coalesce, [{:name, [:title]}, {:value, "F"}]}}]}] =
               module.__hologram_migration__().ops
    end

    test "accepts a pin with a segment type named like an argument" do
      for pin <- [~S|"a#{1}"|, ~S|<<"a1"::binary>>|] do
        assert %Value{term: {:coalesce, [{:name, [:binary]}, {:value, "a1"}]}} =
                 backfill("fn binary -> coalesce(binary, ^#{pin}) end")
      end
    end

    test "accepts a pin piping into a function named like an argument" do
      body = ~S[fn title -> coalesce(title, ^("F" |> title)) end]

      module = compile_migration("20260813091522", op_with(body, "def title(x), do: x"))

      assert [%{opts: [backfill: %Value{term: {:coalesce, [_title, {:value, "F"}]}}]}] =
               module.__hologram_migration__().ops
    end

    test "accepts quoted code inside a pin naming an argument" do
      assert %Value{term: {:coalesce, [_title, {:value, "title"}]}} =
               backfill(
                 ~S|fn title -> coalesce(title, ^to_string(elem(quote(do: title), 0))) end|
               )
    end

    test "names an argument a pin reads where no pattern binds it" do
      for pin <- [
            ~S|to_string(String.match?(title, ~r/a/))|,
            ~S|(cond do title -> "a"; true -> "b" end)|,
            ~S|(case "a" do x when x == title -> x end)|,
            ~S|(<<x::size(title), _::bitstring>> = "ab"; to_string(x))|
          ] do
        assert refusal("fn title -> coalesce(title, ^#{pin}) end") =~
                 "a backfill fn reads its argument title by name, not pinned"
      end
    end

    test "names an argument a pin reads beside a binding of another argument's name" do
      for pin <- [
            ~S|Enum.map_join([title], fn other -> other end)|,
            ~S|(case "a" do ^title -> "b" end)|,
            ~S|<<1::integer-size(title)-little>>|,
            ~S|<<1::title*8>>|,
            ~S|inspect(quote(do: unquote(title)))|
          ] do
        assert refusal(
                 "fn title, other -> coalesce(title, other, ^(#{pin}; fn other -> other end)) end"
               ) =~ "a backfill fn reads its argument title by name, not pinned"
      end
    end

    test "accepts a piped match? binding an argument's name inside a pin" do
      for match <- [
            ~S[{title, _} |> match?({"a", 1})],
            ~S[{title, _} |> Kernel.match?({"a", 1})]
          ] do
        assert %Value{term: {:coalesce, [_title, {:value, "true"}]}} =
                 backfill("fn title -> coalesce(title, ^to_string(#{match})) end")
      end
    end

    test "accepts quoted code that doesn't unquote an argument" do
      for quoted <- [
            "quote(unquote: false, do: unquote(title))",
            "quote([0, {:unquote, false}, {:do, unquote(title)}])",
            "quote([0, {:unquote, false}], [0, {:do, unquote(title)}])",
            "quote(do: quote(do: unquote(title)))",
            "quote(do: Foo.unquote_splicing(title))",
            "quote(do: title |> unquote())",
            "quote(do: title |> Foo.unquote())"
          ] do
        assert %Value{term: {:coalesce, [_title, {:value, value}]}} =
                 backfill("fn title -> coalesce(title, ^inspect(#{quoted})) end")

        assert value =~ "unquote"
      end
    end

    test "accepts a quote whose options only the compiler can read" do
      for {attributes, quoted} <- [
            {"@options [unquote: false]", "quote(@options, do: unquote(title))"},
            {"@off false", "quote(unquote: @off, do: unquote(title))"}
          ] do
        body = "fn title -> coalesce(title, ^inspect(#{quoted})) end"

        module = compile_migration("20260813091522", op_with(body, attributes))

        assert [%{opts: [backfill: %Value{term: {:coalesce, [_title, {:value, value}]}}]}] =
                 module.__hologram_migration__().ops

        assert value =~ "unquote"
      end
    end

    test "accepts a destructure inside a pin binding an argument's name" do
      for call <- ["destructure", "Kernel.destructure"] do
        body = ~s|fn title -> coalesce(title, ^(#{call}([title], ["a"]); title)) end|

        module = compile_migration("20260813091522", op_with(body, ""))

        assert [
                 %{
                   opts: [backfill: %Value{term: {:coalesce, [{:name, [:title]}, {:value, "a"}]}}]
                 }
               ] =
                 module.__hologram_migration__().ops
      end
    end

    test "names an argument a quote reads through its options or a remote unquote" do
      for quoted <- [
            "quote(bind_quoted: [x: title], do: x)",
            "quote(line: title, do: 1)",
            "quote(do: Foo.unquote(title)())",
            "quote(do: unquote(title).unquote(:foo)())",
            "quote(do: 1 |> unquote(title))",
            "quote(do: title = unquote(title))",
            "quote(do: quote([line: unquote(title)], do: 1))",
            "quote([], [unquote: false, do: unquote(title)])"
          ] do
        assert refusal("fn title -> coalesce(title, ^inspect(#{quoted})) end") =~
                 "a backfill fn reads its argument title by name, not pinned"
      end
    end

    test "leaves a malformed cond in a pin to the compiler" do
      for cond_body <- ["cond do end", "cond do 1 end", "cond do [1] end"] do
        assert_raise CompileError, fn ->
          backfill("fn title -> coalesce(title, ^(#{cond_body})) end")
        end
      end
    end

    test "accepts a pinned attribute named like an argument" do
      body = """
      @title "Untitled"
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> coalesce(title, ^@title) end
      end
      """

      [op] = compile_migration("20260813091522", body).__hologram_migration__().ops

      assert %Value{term: {:coalesce, [{:name, [:title]}, {:value, "Untitled"}]}} =
               op.opts[:backfill]
    end

    test "refuses a body reading nothing of the row, naming the constant form" do
      for expression <- [
            ~s|fn title -> coalesce("a", "b") end|,
            ~s|fn title -> query("a" <> "b") end|,
            "fn title -> ~D[2020-01-01] end",
            "fn title -> [1] end",
            "fn title -> %{a: 1} end",
            "fn title -> coalesce(^@a, ^@b) end"
          ] do
        assert refusal(expression) =~ "write it without the fn"
      end
    end

    test "refuses query(...) holding only a pin" do
      assert refusal("fn title -> query(^other) end") =~ "write it without the fn"
    end

    test "reads a piped query(...) as the marker" do
      assert %Value{args: [:title], term: {:name, [:title]}} =
               fn_backfill("fn title -> title |> query() end")
    end

    test "refuses a module defining query/1 beside a piped marker" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> title |> query() end
      end

      defp query(value), do: value
      """

      assert compiled_refusal(body) =~ "can't define query/1 beside it"
    end

    test "refuses a word an import below the op changes" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :integer, backfill: fn tags -> count(tags) end
      end

      import Enum, only: [count: 1]
      """

      assert compiled_refusal(body) =~
               "calls count/1, which an import changes between the op and the end of the " <>
                 "module - put the import at the top of the module"
    end

    test "accepts a body reading one argument twice" do
      module =
        compile_migration(
          "20260813091522",
          op_with("fn title -> coalesce(title, title) end", "")
        )

      assert [%{opts: [backfill: %Value{args: [:title], term: {:coalesce, _terms}}]}] =
               module.__hologram_migration__().ops
    end

    test "still names an unlisted field beside an argument read twice" do
      assert refusal("fn title -> coalesce(name, title, title) end") =~
               "a backfill fn reads name, which isn't among its arguments"
    end

    test "compares a bare pipe target's import too" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> title |> reverse end
      end

      import Enum, only: [reverse: 1]
      """

      assert compiled_refusal(body) =~
               "calls reverse/1, which an import changes between the op and the end of the " <>
                 "module - put the import at the top of the module"
    end

    test "doesn't read a bare pipe target as the argument sharing its name" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn shout -> "abc" |> shout end
      end

      defp shout(value), do: value <> "!"
      """

      assert compiled_refusal(body) =~ "a backfill fn reads the row"
    end

    test "compares the import of a pipe spelled as a remote call too" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> Kernel.|>(title, reverse()) end
      end

      import Enum, only: [reverse: 1]
      """

      assert compiled_refusal(body) =~ "calls reverse/1, which an import changes"
    end

    test "compares the import of a one-argument remote pipe too" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> title |> Kernel.|>(reverse) end
      end

      import Enum, only: [reverse: 1]
      """

      assert compiled_refusal(body) =~ "calls reverse/1, which an import changes"
    end

    test "compares the import of a call in a pipe nested on the right too" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> title |> (reverse() |> hd()) end
      end

      import Enum, only: [reverse: 1]
      """

      assert compiled_refusal(body) =~ "calls reverse/1, which an import changes"
    end

    test "doesn't read a remote pipe's bare target as the argument sharing its name" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn shout -> Kernel.|>("abc", shout) end
      end

      defp shout(value), do: value <> "!"
      """

      assert compiled_refusal(body) =~ "a backfill fn reads the row"
    end

    test "refuses an import written as a bare pipe target inside a body" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title ->
          Enum |> import
          title
        end
      end
      """

      assert compiled_refusal(body) =~ "an Elixir backfill fn can't import inside its body"
    end

    test "still sees an import written as the receiver of a remote pipe" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title ->
          import(Kernel, except: [to_string: 1]).|>(title, is_binary)
          to_string(title)
        end
      end

      defp to_string(value), do: value <> "!"
      """

      assert compiled_refusal(body) =~ "an Elixir backfill fn can't import inside its body"
    end

    test "compares the import of the pipe operator itself" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> title |> String.trim("x") end
      end

      import Kernel, except: [|>: 2]

      defp left |> right, do: left <> "+" <> right
      """

      assert compiled_refusal(body) =~ "calls |>/2, which an import changes"
    end

    test "reads a migration's own pipe operator as a call with a value on its right" do
      {module, _value} =
        elixir_op(
          ~s/fn suffix -> "abc" |> suffix end/,
          "import Kernel, except: [|>: 2]\n\ndefp left |> right, do: left <> right"
        )

      assert module.__backfill_0__("!") == "abc!"
    end

    test "compares a captured call's import too" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :integer, backfill: fn tags -> Enum.map(tags, &count/1) end
      end

      import Enum, only: [count: 1]
      """

      assert compiled_refusal(body) =~ "calls count/1, which an import changes"
    end

    test "refuses a pinned call an import changes below the op, in each form" do
      for backfill <- [
            ~s|fn title -> query(coalesce(title, ^to_iso8601(~U[2020-01-01 00:00:00Z]))) end|,
            ~s|coalesce(title, ^to_iso8601(~U[2020-01-01 00:00:00Z]))|,
            ~s|^to_iso8601(~U[2020-01-01 00:00:00Z])|
          ] do
        body = """
        import DateTime, only: [to_iso8601: 1]

        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: #{backfill}
        end

        import DateTime, only: []
        import NaiveDateTime, only: [to_iso8601: 1]
        """

        assert compiled_refusal(body) =~
                 "a migration op calls to_iso8601/1, which an import changes between the op " <>
                   "and the end of the module"
      end
    end

    test "doesn't count a capture's name as reading an argument" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn count -> Enum.map(["a"], &count/1) end
      end

      defp count(value), do: value
      """

      assert compiled_refusal(body) =~ "write it without the fn"
    end

    test "refuses a query with no filter, naming the shape it takes" do
      for expression <- [
            "fn id -> MyApp.Stop |> count() end",
            "fn id -> count(MyApp.Stop) end",
            "fn id -> MyApp.Stop |> take(1) |> count() end",
            "fn id -> MyApp.Stop |> filter(true) |> count() end"
          ] do
        assert refusal(expression) =~ "a backfill fn queries the rows pointing at this one"
      end
    end

    test "refuses a module defining query/1 beside a nested or piped call" do
      for expression <- [
            "fn title -> String.upcase(query(title)) end",
            "fn title -> title |> query() |> String.upcase() end"
          ] do
        assert compiled_refusal(op_with(expression, "defp query(value), do: value")) =~
                 "can't define query/1 beside it"
      end
    end

    test "refuses an Elixir body using only its own variables" do
      for expression <- [
            ~s|fn title -> x = "a"; x end|,
            "fn title -> for x <- [1], do: x end"
          ] do
        assert refusal(expression) =~ "write it without the fn"
      end
    end

    test "refuses a query naming its type through an attribute" do
      assert refusal("fn id -> @mod.Stop |> filter(trip_id == ^id) |> count() end") =~
               "names the type it queries by its module"
    end

    test "refuses no arguments" do
      assert refusal(~s(fn -> "x" end)) =~ "write it without the fn"
    end

    test "refuses an unpinned attribute in a query body, naming the pin" do
      assert refusal("fn title -> coalesce(title, @fallback) end") =~ "pinned: ^@fallback"
    end

    test "refuses a name that isn't an argument" do
      assert refusal(~s|fn title -> coalesce(title, nickname) end|) =~
               "reads nickname, which isn't among its arguments - add it: " <>
                 "fn title, nickname -> ..."
    end

    test "refuses an argument that's pinned" do
      assert refusal(~s|fn title -> coalesce(^title, "x") end|) =~
               "reads its argument title by name, not pinned"
    end

    test "refuses each malformed argument list" do
      for expression <- [
            "fn %{a: a} -> a end",
            "fn a \\\\ 1 -> a end",
            "fn _ -> 1 end",
            "fn a when is_nil(a) -> a end"
          ] do
        assert refusal(expression) =~ "takes bare field names as its arguments"
      end
    end

    test "refuses a repeated argument" do
      assert refusal("fn a, a -> a end") =~ "names a twice"
    end

    test "refuses several clauses" do
      assert refusal("fn nil -> 1; a -> a end") =~ "has one clause"
    end

    test "treats a word the file imports as Elixir" do
      module =
        compile_migration(
          "20260813091522",
          op_with("fn title -> count(title) end", "import Enum, only: [count: 1]")
        )

      assert [%{opts: [backfill: %Value{term: {:function, ^module, :__backfill_0__, [:title]}}]}] =
               module.__hologram_migration__().ops

      assert module.__backfill_0__([1, 2]) == 2
    end

    test "refuses use Hologram.DB rather than reading its stub in a backfill" do
      body = """
      use Hologram.DB

      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn tags -> tags |> most_common(name) end
      end
      """

      refusal = compiled_refusal(body)

      assert refusal =~ "uses Hologram.DB at compile time"
      refute refusal =~ "is reserved"
    end

    test "refuses use Hologram.DB below an op rather than calling it an import change" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn tags -> tags |> most_common(name) end
      end

      use Hologram.DB
      """

      refusal = compiled_refusal(body)

      assert refusal =~ "uses Hologram.DB at compile time"
      refute refusal =~ "an import changes"
    end

    test "treats a word the module defines below the op as Elixir" do
      body = """
      @fallback "a"
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> coalesce(title, @fallback) end
      end
      @fallback "b"

      defp coalesce(left, right), do: left || right
      """

      module = compile_migration("20260813091522", body)

      assert module.__backfill_0__(nil) == "a"
      assert module.__backfill_0__("x") == "x"
    end

    test "lets the word win inside query(...), over a function of that name" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> query(coalesce(title, "x")) end
      end

      def coalesce(left, right), do: left || right
      """

      [op] = compile_migration("20260813091522", body).__hologram_migration__().ops

      assert %Value{term: {:coalesce, [{:name, [:title]}, {:value, "x"}]}} = op.opts[:backfill]
    end

    test "refuses a module defining query/1 beside a marked body" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn title -> query(title) end
      end

      def query(value), do: value
      """

      assert compiled_refusal(body) =~ "can't define query/1 beside it - rename the function"
    end

    test "refuses an operator beside a word, naming query(...)" do
      assert refusal(~s|fn title -> coalesce(title, "x") <> "!" end|) =~
               "wrap the whole body in query(...)"
    end
  end

  describe "read_fn/2 and choose_fn!/2, an Elixir body" do
    defp compiled(body), do: compile_migration("20260813091522", body)

    defp elixir_op(expression, extra \\ "") do
      module =
        compiled("""
        #{extra}
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: #{expression}
        end
        """)

      [op] = module.__hologram_migration__().ops

      {module, op.opts[:backfill]}
    end

    test "runs as a generated function of the migration" do
      {module, value} = elixir_op("fn title -> String.upcase(title) end")

      assert %Value{args: [:title], term: {:function, ^module, :__backfill_0__, [:title]}} = value
      assert module.__backfill_0__("a") == "A"
    end

    test "keeps a pipe in a quote as data, whatever its receiver" do
      {module, _value} =
        elixir_op(~S"fn title -> title <> inspect(quote(do: (1 |> 2).|>(x, 3))) end")

      assert module.__backfill_0__("a") =~ ~r/^a.*\|>/
    end

    test "takes the arguments in the order written" do
      {module, value} = elixir_op(~s|fn last, first -> first <> " " <> last end|)

      assert %Value{args: [:last, :first], term: {:function, ^module, name, [:last, :first]}} =
               value

      assert apply(module, name, ["Lee", "Ann"]) == "Ann Lee"
    end

    test "gives two backfills on one line distinct functions" do
      module =
        compiled("""
        change_entity MyApp.Trip do
          add_attribute :a, :string, backfill: fn x -> String.upcase(x) end; add_attribute :b, :string, backfill: fn x -> String.downcase(x) end
        end
        """)

      assert [%{opts: [backfill: first]}, %{opts: [backfill: second]}] =
               module.__hologram_migration__().ops

      assert {:function, ^module, a, [:x]} = first.term
      assert {:function, ^module, b, [:x]} = second.term
      assert a != b
      assert apply(module, a, ["MiXeD"]) == "MIXED"
      assert apply(module, b, ["MiXeD"]) == "mixed"
    end

    test "reads a plain attribute's value at the op" do
      {module, _value} = elixir_op(~s|fn title -> title <> @suffix end|, ~s|@suffix "!"|)

      assert module.__backfill_0__("a") == "a!"
    end

    test "reads an attribute reassigned below the op at its value at the op" do
      module =
        compiled("""
        @suffix "!"
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> title <> @suffix end
        end
        @suffix "?"
        """)

      assert module.__backfill_0__("a") == "a!"
    end

    test "resolves an alias where the op is written" do
      module =
        compiled("""
        alias String, as: Text
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> Text.upcase(title) end
        end
        alias Enum, as: Text
        """)

      assert module.__backfill_0__("a") == "A"
    end

    test "calls the migration's own private function" do
      module =
        compiled("""
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> shout(title) end
        end

        defp shout(text), do: String.upcase(text) <> "!"
        """)

      assert module.__backfill_0__("a") == "A!"
    end

    test "reads a field of a value through the strict read" do
      {module, _value} = elixir_op("fn created_at -> Integer.to_string(created_at.year) end")

      assert module.__backfill_0__(~U[2026-01-02 00:00:00Z]) == "2026"
      assert_raise BadMapError, fn -> module.__backfill_0__(String) end
    end

    test "keeps a field access a quote holds as data" do
      {module, _value} = elixir_op("fn title -> Macro.to_string(quote(do: x.y)) <> title end")

      assert module.__backfill_0__("!") == "x.y!"
    end

    test "refuses an alias, import or require inside the body" do
      for {kind, line} <- [
            alias: "alias String, as: S",
            import: "import String",
            require: "require Integer"
          ] do
        assert refusal("fn title -> #{line}; String.upcase(title) end") =~
                 "put the #{kind} at the top of the module"
      end
    end

    # Collected from this compile alone, since stderr takes other tests' output too.
    test "emits no warning for the side of a fn that didn't run" do
      {_module, diagnostics} =
        Code.with_diagnostics(fn ->
          compiled("""
          @suffix "!"
          change_entity MyApp.Trip do
            add_attribute :value, :string, backfill: fn title -> query(title <> ^@suffix) end
          end
          """)
        end)

      assert Enum.map(diagnostics, & &1.message) == []
    end

    test "keeps a pin inside match?, however it's spelled" do
      for {call, extra} <- [
            {"match?(^b, a)", ""},
            {"Kernel.match?(^b, a)", ""},
            {"Elixir.Kernel.match?(^b, a)", ""},
            {"K.match?(^b, a)", "alias Kernel, as: K"},
            {"^b |> match?(a)", ""}
          ] do
        {module, _value} =
          elixir_op(~s(fn a, b -> if #{call}, do: "same", else: "other" end), extra)

        assert module.__backfill_0__(1, 1) == "same"
        assert module.__backfill_0__(1, 2) == "other"
      end
    end

    test "keeps a pin inside destructure, however it's spelled" do
      for {call, extra} <- [
            {"destructure([^b, rest], a)", ""},
            {"Kernel.destructure([^b, rest], a)", ""},
            {"Elixir.Kernel.destructure([^b, rest], a)", ""},
            {"K.destructure([^b, rest], a)", "alias Kernel, as: K"},
            {"[^b, rest] |> destructure(a)", ""}
          ] do
        {module, _value} = elixir_op(~s(fn a, b -> #{call}; rest end), extra)

        assert module.__backfill_0__(["x", "y"], "x") == "y"
        assert_raise MatchError, fn -> module.__backfill_0__(["x", "y"], "z") end
      end
    end

    test "refuses the migration's macro in a guard" do
      body = """
      @o "1"
      defmacrop same(x), do: quote(do: unquote(x) == @o)

      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn t ->
          case t do
            x when same(x) -> x
            _other -> "other"
          end
        end
      end

      @o "2"
      """

      error = assert_raise Hologram.CompileError, fn -> compiled(body) end

      assert error.message =~
               "can't call the migration's macro same/1 - make it a defp, or a defguardp in a " <>
                 "guard"
    end

    test "accepts a guard the migration defines" do
      module =
        compiled("""
        defguardp is_short(x) when byte_size(x) < 3

        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn t ->
            case t do
              x when is_short(x) -> x
              _other -> "long"
            end
          end
        end
        """)

      assert module.__backfill_0__("ab") == "ab"
      assert module.__backfill_0__("abcd") == "long"
    end

    test "refuses a pin in a cond head" do
      assert refusal(~s|fn a, b -> cond do ^b -> a; true -> "x" end end|) =~
               "so it pins nothing"
    end

    test "refuses a pin in a guard" do
      assert refusal(~s|fn a, b -> case a do x when x == ^b -> x; _o -> "n" end end|) =~
               "so it pins nothing"
    end

    test "refuses a call to the migration's own macro" do
      for kind <- ["defmacro", "defmacrop"] do
        body = """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title -> shout(title) end
        end

        #{kind} shout(text), do: text
        """

        error = assert_raise Hologram.CompileError, fn -> compiled(body) end

        assert error.message =~ "can't call the migration's macro shout/1 - make it a defp"
      end
    end

    test "refuses a function holding the generated name" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string, backfill: fn x -> String.upcase(x) end
      end

      def __backfill_0__(_x), do: "mine"
      """

      error = assert_raise Hologram.CompileError, fn -> compiled(body) end

      assert error.message =~ "__backfill_0__/1 is the name a backfill fn runs under"
    end

    test "names the Elixir function for a word beside an operator a query can't read" do
      assert refusal(~s|fn a -> at(a, 0) <> "!" end|) =~ "write Enum.at/2"

      assert refusal(~s|fn a -> String.upcase(a) <> coalesce(a, "x") end|) =~ "has no query"
    end

    test "refuses query(...) nested in an Elixir body" do
      assert refusal("fn a -> String.upcase(query(a)) end") =~
               "query(...) wraps the whole body of a backfill fn"
    end

    test "keeps a pin inside a pattern" do
      {module, _value} = elixir_op("fn a, b -> case a do ^b -> 1; _other -> 2 end end")

      assert module.__backfill_0__(1, 1) == 1
      assert module.__backfill_0__(1, 2) == 2
    end

    test "refuses a pin outside a pattern" do
      assert refusal(~s|fn title -> String.upcase(^title) end|) =~
               "gets the row's values as its arguments, so it pins nothing"
    end

    test "takes a pin inside a quote as data" do
      {module, _value} =
        elixir_op(~s|fn title -> Macro.to_string(quote(do: ^value)) <> title end|)

      assert module.__backfill_0__("a") == "^valuea"
    end

    test "keeps an alias inside a quote as written" do
      {module, _value} =
        elixir_op(
          ~s|fn t -> Macro.to_string(quote(do: Short.x())) <> t end|,
          "alias MyApp.Short"
        )

      assert module.__backfill_0__("a") == "Short.x()a"
    end

    test "binds an alias inside a quote where the op is written" do
      module =
        compiled("""
        alias MyApp.Short

        change_entity MyApp.Trip do
          add_attribute :value, :string,
            backfill: fn t -> inspect(Keyword.get(elem(quote(do: Short), 1), :alias)) <> t end
        end

        alias MyApp.Long.Short

        delete_entity Short
        """)

      assert module.__backfill_0__("a") == "MyApp.Shorta"
    end

    test "marks an alias inside a quote that no alias applies to as unaliased" do
      {module, _value} =
        elixir_op(~s|fn t -> inspect(Keyword.get(elem(quote(do: Nope), 1), :alias)) <> t end|)

      assert module.__backfill_0__("a") == "falsea"
    end

    test "keeps an alias inside a quote of a pinned value as written, expanding what it unquotes" do
      {_module, value} =
        elixir_op(
          ~s|fn t -> coalesce(t, ^Macro.to_string(quote(do: Short.x(unquote(Short))))) end|,
          "alias MyApp.Short"
        )

      assert %Value{term: {:coalesce, [_t, {:value, "Short.x(MyApp.Short)"}]}} = value
    end

    test "refuses split and at, naming the Elixir function" do
      assert refusal(~s|fn title -> String.trim(split(title, ",")) end|) =~ "write String.split/2"
      assert refusal(~s|fn title -> String.trim(at(title, 0)) end|) =~ "write Enum.at/2"
    end

    test "takes a query word inside a quote as data" do
      {module, _value} =
        elixir_op(~s|fn title -> inspect(quote(do: split(title, ","))) <> title end|)

      assert module.__backfill_0__("a") =~ ~r/^\{:split, \[\], \[\{:title, .*\}a$/
    end

    test "takes query(...) inside a quote as data, beside a query/1 of the module too" do
      for extra <- ["", "def query(value), do: value"] do
        {module, _value} =
          elixir_op(~s|fn title -> inspect(quote(do: query(title))) <> title end|, extra)

        assert module.__backfill_0__("a") =~ ~r/^\{:query, \[\], \[\{:title, .*\}a$/
      end
    end

    test "compares the import of a call inside a quote, which the quote records" do
      body = """
      change_entity MyApp.Trip do
        add_attribute :value, :string,
          backfill: fn title -> inspect(quote(do: split(title, ","))) <> title end
      end

      import String, only: [split: 2]
      """

      assert compiled_refusal(body) =~
               "calls split/2, which an import changes between the op and the end of the " <>
                 "module - put the import at the top of the module"
    end

    test "refuses a query word in a quote's options, which run" do
      assert refusal(
               ~s|fn title -> inspect(quote(bind_quoted: [x: split(title, ",")], do: x)) end|
             ) =~
               "write String.split/2"
    end

    test "takes a pin in a bitstring generator's pattern" do
      {module, _value} =
        elixir_op(
          ~S|fn title -> marker = ?a; for <<^marker, byte <- title>>, into: "", do: <<byte>> end|
        )

      assert module.__backfill_0__("abac") == "bc"
    end

    test "refuses a pin in a bitstring generator's source" do
      assert compiled_refusal(~S|change_entity MyApp.Trip do
                 add_attribute :value, :string,
                   backfill: fn title -> marker = "a"; for <<byte <- ^marker>>, into: title, do: <<byte>> end
               end|) =~ "so it pins nothing"
    end

    test "takes what a quote with separate options ignores beside the do as data" do
      {module, _value} =
        elixir_op(
          ~s|fn title -> inspect(quote([], bind_quoted: [y: split(title, ",")], do: 1)) <> title end|
        )

      assert module.__backfill_0__("a") == "1a"
    end

    test "takes the first do of any list a quote takes as data" do
      for quoted <- [
            ~s|quote([], [0, {:do, split(title, ",")}, {:do, title}])|,
            ~s|quote([0, {:do, split(title, ",")}])|
          ] do
        {module, _value} = elixir_op("fn title -> inspect(#{quoted}) <> title end")

        assert module.__backfill_0__("a") =~ ~r/^\{:split, \[\], \[\{:title, .*\}, ","\]\}a$/
      end
    end

    test "takes a call to the migration's own macro inside a quote as data" do
      for kind <- ["defmacro", "defmacrop"] do
        {module, _value} =
          elixir_op(
            ~s|fn title -> inspect(quote(do: shout(title))) <> title end|,
            "#{kind} shout(text), do: text"
          )

        assert module.__backfill_0__("a") =~ ~r/^\{:shout, \[\], \[\{:title, .*\}a$/
      end
    end

    test "takes an alias, an import or a require inside a quote as data" do
      for kind <- ["alias", "import", "require"] do
        {module, _value} =
          elixir_op(~s|fn title -> inspect(quote(do: #{kind}(String))) <> title end|)

        assert module.__backfill_0__("a") =~ ~r/^\{:#{kind}, .*a$/
      end
    end

    test "refuses an import or the migration's own macro in a quote's options, which run" do
      for {call, message} <- [
            {"import(String, only: [trim: 1])", "can't import inside its body"},
            {"shout(title)", "can't call the migration's macro shout/1"}
          ] do
        body = """
        change_entity MyApp.Trip do
          add_attribute :value, :string, backfill: fn title ->
            inspect(quote(bind_quoted: [x: #{call}], do: x)) <> title
          end
        end

        defmacro shout(text), do: text
        """

        assert compiled_refusal(body) =~ message
      end
    end

    test "refuses an unquote even inside a quote" do
      for expression <- [
            "quote(do: unquote(title))",
            "quote(do: [unquote_splicing([title])])",
            "quote(unquote: false, do: unquote(title))",
            "quote(do: String.unquote(:upcase)(title))",
            "quote(do: title |> String.unquote(:upcase))"
          ] do
        assert refusal("fn title -> inspect(#{expression}) <> title end") =~
                 ~r/can't unquote(_splicing)? inside its body - read a value of the file as @x/
      end
    end

    test "refuses the other words, saying it has no query" do
      for word <- [
            "count(title)",
            "most_common(title, name)",
            ~s|coalesce(title, "x")|,
            "filter(title, a == 1)"
          ] do
        message = refusal("fn title -> String.trim(#{word}) end")

        assert message =~ "has no query"
        refute message =~ "query(...)"
      end
    end

    test "refuses an app call through the call check" do
      assert_raise Hologram.CompileError, ~r/MyApp.Slug/, fn ->
        elixir_op("fn title -> MyApp.Slug.make(title) end")
      end
    end

    test "refuses a capture in place of a fn" do
      assert refusal("&String.upcase/1") =~ "a capture hides the fields it reads"
    end
  end

  describe "lower/2, refusals" do
    test "refuses a call that is no word, naming the words and the pin" do
      assert refusal("upcase(title)") ==
               "upcase/1 is no backfill word - the words are <>, split, at, coalesce, count " <>
                 "and most_common, and a value from the surrounding code is pinned with ^"
    end

    test "refuses an operator that is no word" do
      assert refusal("price * 100") =~ "*/2 is no backfill word"
    end

    test "refuses a module attribute naming the pin" do
      assert refusal("coalesce(nickname, @fallback)") =~ "pinned: ^@fallback"
    end

    test "refuses a module attribute at the top naming the pin" do
      assert refusal("@fallback") =~ "pinned: ^@fallback"
    end

    test "refuses a sigil naming the pin" do
      assert refusal("~D[2026-01-02]") =~ "pinned: ^~D[2026-01-02]"
    end

    test "refuses a map naming the pin" do
      assert refusal("%{a: 1}") =~ "pinned: ^%{a: 1}"
    end

    test "refuses a tuple naming the pin" do
      assert refusal("{1, 2}") =~ "pinned: ^{1, 2}"
    end

    test "refuses a list naming the pin" do
      assert refusal("[1, 2]") =~ "pinned: ^[1, 2]"
    end

    test "refuses a remote call naming the pin" do
      assert refusal("String.upcase(title)") =~ "pinned: ^String.upcase(title)"
    end

    test "refuses an interpolated string naming <>" do
      assert refusal(~S|"Trip to #{destination}"|) =~ "a backfill joins strings with <>"
    end

    test "refuses a pipe into something that is no call" do
      assert refusal("title |> 1") ==
               "a backfill pipes into a word called with parentheses, got: 1"
    end

    test "refuses a pipe into a fn" do
      assert refusal("title |> fn x -> x end") =~ "a backfill pipes into a word"
    end

    test "refuses a pipe into a map" do
      assert refusal("title |> %{}") =~ "a backfill pipes into a word"
    end

    test "refuses a pipe into a binary" do
      assert refusal("title |> <<1>>") =~ "a backfill pipes into a word"
    end

    test "refuses a pipe into a sigil" do
      assert refusal("title |> ~D[2026-01-02]") =~ "a backfill pipes into a word"
    end

    test "refuses a pipe into a block" do
      assert refusal("title |> (a; b)") =~ "a backfill pipes into a word"
    end

    test "refuses a query stage at the top naming the fn form" do
      assert refusal("MyApp.Stop |> sort(a)") =~
               "for the rows pointing at this one, write a fn naming its id"
    end

    test "refuses a paginated query from a type naming the fn form" do
      assert refusal("MyApp.Stop |> paginate(1) |> count()") =~
               "for the rows pointing at this one, write a fn naming its id"
    end

    test "refuses a binary literal naming the pin" do
      assert refusal("<<1, 2>>") =~ "pinned: ^<<1, 2>>"
    end

    test "refuses an alias headed by an attribute naming the pin" do
      assert refusal("@mod.Tier") =~ "pinned: ^@mod.Tier"
    end

    test "refuses a nested fn" do
      assert refusal("coalesce(title, fn x -> x end)") =~
               "a fn goes at the top of backfill:, got one inside the expression"
    end

    test "refuses a capture naming the fn form" do
      assert refusal("&String.upcase/1") =~ "a capture hides the fields it reads"
    end

    test "refuses a nested capture naming the fn form" do
      assert refusal("coalesce(title, &String.upcase/1)") =~ "a capture hides the fields it reads"
    end
  end
end
