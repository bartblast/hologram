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
      assert backfill("7") == 7
    end

    test "keeps a float" do
      assert backfill("1.5") == 1.5
    end

    test "keeps a signed number" do
      assert backfill("-7") == -7
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

    test "refuses a fn for now" do
      assert refusal("fn title -> title end") ==
               "a backfill can't take a fn yet - write the expression without it"
    end

    test "refuses a nested fn" do
      assert refusal("coalesce(title, fn x -> x end)") ==
               "a backfill can't take a fn yet - write the expression without it"
    end

    test "refuses a capture naming the fn form" do
      assert refusal("&String.upcase/1") =~ "a capture hides the fields it reads"
    end

    test "refuses a nested capture naming the fn form" do
      assert refusal("coalesce(title, &String.upcase/1)") =~ "a capture hides the fields it reads"
    end
  end
end
