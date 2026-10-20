defmodule Hologram.Query.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Expression

  # The code is parsed at line 12 of a stage call made at line 7, so a refusal located at a node
  # names line 12 and one located at a node carrying no line (a literal) names the call's line.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/queries.ex"), line: 7}
  end

  defp lower_predicates(code, binding \\ []) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> predicates(env())
      |> Code.eval_quoted(binding)

    value
  end

  describe "predicates/2" do
    test "keeps a pinned keyword value an equality operand" do
      assert lower_predicates("[status: ^statuses]", statuses: [:todo]) ==
               [status: {:==, [:todo]}]
    end

    test "lowers a comparison with a module name" do
      assert lower_predicates("entity_type == MyApp.Trip") == [entity_type: {:==, MyApp.Trip}]
    end

    test "lowers a comparison with a negative number" do
      assert lower_predicates("priority > -7") == [priority: {:>, -7}]
    end

    test "lowers a comparison with nil" do
      assert lower_predicates("archived_at == nil") == [archived_at: {:==, nil}]
    end

    test "lowers a conjunction of three predicates" do
      assert lower_predicates(~s(a == true and b > 1 and c != "x")) ==
               [a: {:==, true}, b: {:>, 1}, c: {:!=, "x"}]
    end

    test "lowers a keyword list of literals" do
      assert lower_predicates(~s([project_id: "p", status: :todo])) ==
               [project_id: {:==, "p"}, status: {:==, :todo}]
    end

    test "lowers a keyword list with pinned values" do
      assert lower_predicates("[project_id: ^project_id, owner_id: ^user.id]",
               project_id: "p",
               user: %{id: "u"}
             ) == [project_id: {:==, "p"}, owner_id: {:==, "u"}]
    end

    test "lowers a membership in a list literal" do
      assert lower_predicates("status in [:todo, :doing]") == [status: {:in, [:todo, :doing]}]
    end

    test "lowers a membership in a list with a pinned element" do
      assert lower_predicates("b in [^min, 1]", min: 5) == [b: {:in, [5, 1]}]
    end

    test "lowers a membership in a pinned list" do
      assert lower_predicates("status in ^statuses", statuses: [:todo]) ==
               [status: {:in, [:todo]}]
    end

    test "lowers a membership in a range literal" do
      assert lower_predicates("priority in 3..5") == [priority: {:in, 3..5}]
    end

    test "lowers a membership in a range with a pinned bound" do
      assert lower_predicates("priority in 1..^max", max: 4) == [priority: {:in, 1..4}]
    end

    test "lowers a negated membership" do
      assert lower_predicates("status not in [:done]") == [status: {:not_in, [:done]}]
    end

    test "lowers a negated membership in a pinned list" do
      assert lower_predicates("status not in ^statuses", statuses: [:done]) ==
               [status: {:not_in, [:done]}]
    end

    test "lowers a pinned call" do
      assert lower_predicates("created_at > ^Date.add(today, -7)", today: ~D[2026-10-20]) ==
               [created_at: {:>, ~D[2026-10-13]}]
    end

    test "lowers a pinned dot chain" do
      assert lower_predicates("author_id == ^user.id", user: %{id: "u"}) ==
               [author_id: {:==, "u"}]
    end

    test "lowers each comparison operator" do
      assert lower_predicates("b == 1") == [b: {:==, 1}]
      assert lower_predicates("b != 1") == [b: {:!=, 1}]
      assert lower_predicates("b < 1") == [b: {:<, 1}]
      assert lower_predicates("b <= 1") == [b: {:<=, 1}]
      assert lower_predicates("b > 1") == [b: {:>, 1}]
      assert lower_predicates("b >= 1") == [b: {:>=, 1}]
    end

    test "passes a pinned predicates list through" do
      assert lower_predicates("^predicates", predicates: [priority: {:>=, 3}]) ==
               [priority: {:>=, 3}]
    end

    test "raises on a bare name alone" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("done") end
    end

    test "raises on a bare name as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: owner_id reads as an attribute of the queried entity, and an attribute is compared only with a value - a value from the surrounding code is pinned: ^owner_id",
                   fn -> lower_predicates("owner_id == owner_id") end
    end

    test "raises on a bare name as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: project_id reads as an attribute of the queried entity, and an attribute is compared only with a value - a value from the surrounding code is pinned: ^project_id",
                   fn -> lower_predicates("[project_id: project_id]") end
    end

    test "raises on a bare name as a membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a membership operand is a list, a range or a pinned expression, got: statuses - a value from the surrounding code is pinned: ^statuses",
                   fn -> lower_predicates("status in statuses") end
    end

    test "raises on a call as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal or a pinned expression, got: Date.utc_today() - a value from the surrounding code is pinned: ^Date.utc_today()",
                   fn -> lower_predicates("created_at > Date.utc_today()") end
    end

    test "raises on a call as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword predicate value is a literal or a pinned expression, got: String.downcase(search) - a value from the surrounding code is pinned: ^String.downcase(search)",
                   fn -> lower_predicates("[c: String.downcase(search)]") end
    end

    test "raises on a call as a membership element" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a membership element is a literal or a pinned expression, got: f(x) - a value from the surrounding code is pinned: ^f(x)",
                   fn -> lower_predicates("b in [f(x)]") end
    end

    test "raises on a call as a range bound" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a range bound is a literal or a pinned expression, got: f(x) - a value from the surrounding code is pinned: ^f(x)",
                   fn -> lower_predicates("b in 1..f(x)") end
    end

    test "raises on a call as the whole argument" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: open_predicates() - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("open_predicates()") end
    end

    test "raises on a keyword list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword list or a pinned list of predicates is a whole filter, not one side of and, got: [a: 1] - pass it to a filter call of its own",
                   fn -> lower_predicates("[a: 1] and b == 2") end
    end

    test "raises on a list as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: [:todo, :doing]] - write it as an expression: status in [:todo, :doing]",
                   fn -> lower_predicates("[status: [:todo, :doing]]") end
    end

    test "raises on a membership tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:in, [:todo]}] - write it as an expression: status in [:todo]",
                   fn -> lower_predicates("[status: {:in, [:todo]}]") end
    end

    test "raises on a module attribute as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal or a pinned expression, got: @max - a value from the surrounding code is pinned: ^@max",
                   fn -> lower_predicates("priority < @max") end
    end

    test "raises on a negated membership tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:not_in, [:done]}] - write it as an expression: status not in [:done]",
                   fn -> lower_predicates("[status: {:not_in, [:done]}]") end
    end

    test "raises on a negation that is not a membership" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: not done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("not done") end
    end

    test "raises on a non-atom keyword key" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate names an attribute with an atom, got: {key, 1}",
                   fn -> lower_predicates("[{key, 1}]") end
    end

    test "raises on a pinned left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity, got: ^x",
                   fn -> lower_predicates("^x == a") end
    end

    test "raises on a pinned list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword list or a pinned list of predicates is a whole filter, not one side of and, got: ^predicates - pass it to a filter call of its own",
                   fn -> lower_predicates("^predicates and b == 2") end
    end

    test "raises on a range as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword predicate is an equality, got: [priority: 3..5] - write it as an expression: priority in 3..5",
                   fn -> lower_predicates("[priority: 3..5]") end
    end

    test "raises on a range as a negated membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a negated membership takes a list or a pinned expression, got: 3..5",
                   fn -> lower_predicates("priority not in 3..5") end
    end

    test "raises on a sigil as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal or a pinned expression, got: ~D[2026-01-01] - a value from the surrounding code is pinned: ^~D[2026-01-01]",
                   fn -> lower_predicates("created_at > ~D[2026-01-01]") end
    end

    test "raises on a tuple naming no operator as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:foo, 1}] - a comparison, a membership or a range is written as an expression",
                   fn -> lower_predicates("[status: {:foo, 1}]") end
    end

    test "raises on a value on the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: the left side of a comparison names an attribute of the queried entity, got: 3",
                   fn -> lower_predicates("3 <= priority") end
    end

    test "raises on an operator expression as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal or a pinned expression, got: n * 2 - a value from the surrounding code is pinned: ^(n * 2)",
                   fn -> lower_predicates("b > n * 2") end
    end

    test "raises on an operator tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [priority: {:>=, 3}] - write it as an expression: priority >= 3",
                   fn -> lower_predicates("[priority: {:>=, 3}]") end
    end

    test "raises on an or" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: a == 1 or b == 2 - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("a == 1 or b == 2") end
    end

    test "raises on comparisons listed instead of joined" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword predicate is attribute: value, got: a == 1 - join comparisons with and",
                   fn -> lower_predicates("[a == 1, b == 2]") end
    end
  end
end
