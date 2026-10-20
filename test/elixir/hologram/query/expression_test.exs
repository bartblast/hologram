defmodule Hologram.Query.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Expression

  # The code is parsed at line 12 of a stage call made at line 7, so a refusal located at a node
  # names line 12 and one located at a node carrying no line (a literal) names the call's line.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/queries.ex"), line: 7}
  end

  # Parses the code, lowers it with the given lowering and evaluates what it lowered to, with the
  # given binding standing for the caller's variables.
  defp lower(lowering, code, binding \\ []) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> lowering.()
      |> Code.eval_quoted(binding)

    value
  end

  defp lower_bound(code, binding \\ []), do: lower(&bound(&1, :limit, env()), code, binding)

  defp lower_inclusion(code, binding \\ []), do: lower(&inclusion(&1, env()), code, binding)

  defp lower_ordering(code, binding \\ []), do: lower(&ordering(&1, env()), code, binding)

  defp lower_pagination(code, binding \\ []), do: lower(&pagination(&1, env()), code, binding)

  defp lower_predicates(code, binding \\ []), do: lower(&predicates(&1, env()), code, binding)

  defp lower_relationship(code, binding \\ []),
    do: lower(&relationship(&1, env()), code, binding)

  defp lower_sub_builder(code, binding \\ []), do: lower(&sub_builder(&1, env()), code, binding)

  describe "bound/3" do
    test "lowers a negative integer for the stage to judge" do
      assert lower_bound("-1") == -1
    end

    test "lowers a pinned expression" do
      assert lower_bound("^page_size", page_size: 20) == 20
    end

    test "lowers an integer" do
      assert lower_bound("5") == 5
    end

    test "raises on a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: limit takes an integer or a pinned expression, got: page_size - a value from the surrounding code is pinned: ^page_size",
                   fn -> lower_bound("page_size") end
    end

    test "raises on a bare name for offset" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: offset takes an integer or a pinned expression, got: skip - a value from the surrounding code is pinned: ^skip",
                   fn -> lower(&bound(&1, :offset, env()), "skip") end
    end

    test "raises on a dot chain" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: limit takes an integer or a pinned expression, got: bounds.limit - a value from the surrounding code is pinned: ^bounds.limit",
                   fn -> lower_bound("bounds.limit") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: limit takes an integer or a pinned expression, got: :all",
                   fn -> lower_bound(":all") end
    end

    test "raises on an operator expression" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: limit takes an integer or a pinned expression, got: n + 1 - a value from the surrounding code is pinned: ^(n + 1)",
                   fn -> lower_bound("n + 1") end
    end
  end

  describe "inclusion/2" do
    test "absorbs a bare name after a path through it" do
      assert lower_inclusion("[tasks.owner, tasks]") == [tasks: [:owner]]
    end

    test "absorbs a bare name into a path through it" do
      assert lower_inclusion("[tasks, tasks.owner]") == [tasks: [:owner]]
    end

    test "collapses a repeated path" do
      assert lower_inclusion("[tasks.owner, tasks.owner]") == [tasks: [:owner]]
    end

    test "keeps a pinned element in place" do
      assert lower_inclusion("[owner, ^rel]", rel: :project) == [:owner, :project]
    end

    test "keeps a pinned element in place between paths through one relationship" do
      assert lower_inclusion("[tasks.owner, ^rel, tasks.project]", rel: :owner) ==
               [{:tasks, [:owner, :project]}, :owner]
    end

    test "lowers a bare name" do
      assert lower_inclusion("owner") == :owner
    end

    test "lowers a keyword entry with a capture" do
      assert lower_inclusion("[tasks: &Function.identity/1]") ==
               [tasks: &Function.identity/1]
    end

    test "lowers a keyword entry with a pinned sub-builder" do
      assert lower_inclusion("[tasks: ^builder]", builder: &Function.identity/1) ==
               [tasks: &Function.identity/1]
    end

    test "lowers a keyword entry with an in-place fn" do
      assert [tasks: sub_builder] = lower_inclusion("[tasks: fn query -> {:refined, query} end]")
      assert sub_builder.(:query) == {:refined, :query}
    end

    test "lowers a list of names and paths" do
      assert lower_inclusion("[owner, tasks.owner]") == [:owner, tasks: [:owner]]
    end

    test "lowers a path" do
      assert lower_inclusion("tasks.owner") == [tasks: [:owner]]
    end

    test "lowers a three-hop path" do
      assert lower_inclusion("a.b.c") == [a: [b: [:c]]]
    end

    test "merges paths sharing a first hop in the order it first appears" do
      assert lower_inclusion("[tasks.owner, owner, tasks.project]") ==
               [{:tasks, [:owner, :project]}, :owner]
    end

    test "merges paths sharing two hops" do
      assert lower_inclusion("[a.b.c, a.b.d]") == [a: [b: [:c, :d]]]
    end

    test "passes a pinned spec through" do
      assert lower_inclusion("^spec", spec: [project: [:owner]]) == [project: [:owner]]
    end

    test "raises on a call" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: Foo.bar() - a value from the surrounding code is pinned: ^Foo.bar()",
                   fn -> lower_inclusion("Foo.bar()") end
    end

    test "raises on a keyword entry nesting a keyword list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include nests with a path, got: [tasks: [owner: project]] - write it as a path: tasks.owner.project",
                   fn -> lower_inclusion("[tasks: [owner: project]]") end
    end

    test "raises on a keyword entry nesting a list of names" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include nests with a path, got: [tasks: [owner, project]] - write each as a path: tasks.owner, tasks.project",
                   fn -> lower_inclusion("[tasks: [owner, project]]") end
    end

    test "raises on a keyword entry nesting a name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include nests with a path, got: [tasks: owner] - write it as a path: tasks.owner",
                   fn -> lower_inclusion("[tasks: owner]") end
    end

    test "raises on a keyword entry nesting an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include nests with a path, got: [tasks: :owner] - write it as a path: tasks.owner",
                   fn -> lower_inclusion("[tasks: :owner]") end
    end

    test "raises on a keyword entry with an unpinned sub-builder call" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword entry in include pairs a relationship with a sub-builder written in place (fn or &) or a pinned expression, got: [tasks: Foo.builder()] - a value from the surrounding code is pinned: ^Foo.builder()",
                   fn -> lower_inclusion("[tasks: Foo.builder()]") end
    end

    test "raises on a keyword entry with nil" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword entry in include pairs a relationship with a sub-builder written in place (fn or &) or a pinned expression, got: [tasks: nil]",
                   fn -> lower_inclusion("[tasks: nil]") end
    end

    test "raises on a path called with parentheses" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: tasks.owner() - a value from the surrounding code is pinned: ^tasks.owner()",
                   fn -> lower_inclusion("tasks.owner()") end
    end

    test "raises on a remote call without parentheses" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: Foo.bar() - a value from the surrounding code is pinned: ^Foo.bar()",
                   fn -> lower_inclusion("Foo.bar") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include names a relationship with a bare name, got: :owner - write owner",
                   fn -> lower_inclusion(":owner") end
    end

    test "raises on an atom in a list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include names a relationship with a bare name, got: :project - write project",
                   fn -> lower_inclusion("[owner, :project]") end
    end
  end

  describe "ordering/2" do
    test "lowers a bare name" do
      assert lower_ordering("priority") == :priority
    end

    test "lowers a keyword list" do
      assert lower_ordering("[priority: :desc, title: :asc]") == [priority: :desc, title: :asc]
    end

    test "lowers a list mixing names and pairs" do
      assert lower_ordering("[title, {priority, :desc}]") == [:title, {:priority, :desc}]
    end

    test "lowers a list of names" do
      assert lower_ordering("[priority, created_at]") == [:priority, :created_at]
    end

    test "lowers a pinned direction" do
      assert lower_ordering("[title: ^dir]", dir: :desc) == [title: :desc]
    end

    test "lowers a pinned name in a pair" do
      assert lower_ordering("[{^key, :desc}]", key: :title) == [title: :desc]
    end

    test "passes a pinned spec through" do
      assert lower_ordering("^spec", spec: [{:title, :asc}]) == [title: :asc]
    end

    test "raises on a bare direction" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a direction is :asc, :desc or a pinned expression, got: desc",
                   fn -> lower_ordering("[priority: desc]") end
    end

    test "raises on a call" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: order_by names an attribute with a bare name, or with a pinned expression when the name comes from the surrounding code, got: sort_key() - a value from the surrounding code is pinned: ^sort_key()",
                   fn -> lower_ordering("sort_key()") end
    end

    test "raises on a dot path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: order_by names an attribute with a bare name, or with a pinned expression when the name comes from the surrounding code, got: entity.field - a value from the surrounding code is pinned: ^entity.field",
                   fn -> lower_ordering("entity.field") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: order_by names an attribute with a bare name, got: :priority - write priority",
                   fn -> lower_ordering(":priority") end
    end

    test "raises on an atom in a list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: order_by names an attribute with a bare name, got: :created_at - write created_at",
                   fn -> lower_ordering("[priority, :created_at]") end
    end
  end

  describe "pagination/2" do
    test "lowers a pinned option" do
      assert lower_pagination("[page: ^page, size: 25]", page: 2) == [page: 2, size: 25]
    end

    test "lowers integer options" do
      assert lower_pagination("[page: 2, size: 25]") == [page: 2, size: 25]
    end

    test "passes pinned options through" do
      assert lower_pagination("^opts", opts: [page: 1, size: 10]) == [page: 1, size: 10]
    end

    test "raises on a bare name as an option value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a paginate option takes an integer or a pinned expression, got: page - a value from the surrounding code is pinned: ^page",
                   fn -> lower_pagination("[page: page, size: 25]") end
    end

    test "raises on a bare name as the options" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: paginate takes page: and size: options or a pinned expression, got: opts - a value from the surrounding code is pinned: ^opts",
                   fn -> lower_pagination("opts") end
    end
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

  describe "relationship/2" do
    test "lowers a bare name" do
      assert lower_relationship("owner") == [:owner]
    end

    test "lowers a path" do
      assert lower_relationship("project.tasks") == [:project, :tasks]
    end

    test "lowers a pinned name" do
      assert lower_relationship("^rel", rel: :owner) == [:owner]
    end

    test "raises on a call" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: relationship_for(x) - a value from the surrounding code is pinned: ^relationship_for(x)",
                   fn -> lower_relationship("relationship_for(x)") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include names a relationship with a bare name, got: :owner - write owner",
                   fn -> lower_relationship(":owner") end
    end
  end

  describe "sub_builder/2" do
    test "lowers a pinned sub-builder" do
      assert lower_sub_builder("^builder", builder: &Function.identity/1) ==
               (&Function.identity/1)
    end

    test "passes a capture through" do
      assert lower_sub_builder("&Function.identity/1") == (&Function.identity/1)
    end

    test "passes an in-place fn through" do
      sub_builder = lower_sub_builder("fn query -> {:refined, query} end")

      assert sub_builder.(:query) == {:refined, :query}
    end

    test "raises on a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include/3 takes a sub-builder written in place (fn or &) or a pinned expression, got: builder - a value from the surrounding code is pinned: ^builder",
                   fn -> lower_sub_builder("builder") end
    end
  end
end
