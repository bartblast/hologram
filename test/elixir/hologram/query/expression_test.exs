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

  defp lower_bound(code, binding \\ []), do: lower(&bound(&1, :take, env()), code, binding)

  defp lower_condition(code, binding \\ []), do: lower(&condition(&1, env()), code, binding)

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
                   "lib/my_app/queries.ex:12: take takes an integer or a pinned expression, got: page_size - a value from the surrounding code is pinned: ^page_size",
                   fn -> lower_bound("page_size") end
    end

    test "raises on a bare name for skip" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: skip takes an integer or a pinned expression, got: start - a value from the surrounding code is pinned: ^start",
                   fn -> lower(&bound(&1, :skip, env()), "start") end
    end

    test "raises on a dot chain" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: take takes an integer or a pinned expression, got: bounds.limit - a value from the surrounding code is pinned: ^bounds.limit",
                   fn -> lower_bound("bounds.limit") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: take takes an integer or a pinned expression, got: :all",
                   fn -> lower_bound(":all") end
    end

    test "raises on an operator expression" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: take takes an integer or a pinned expression, got: n + 1 - a value from the surrounding code is pinned: ^(n + 1)",
                   fn -> lower_bound("n + 1") end
    end
  end

  describe "condition/2" do
    test "lowers a comparison" do
      assert lower_condition("priority < 3") == [priority: {:<, 3}]
    end

    test "lowers a comparison with a path" do
      assert lower_condition("project.archived == false") == [
               {[:project, :archived], {:==, false}}
             ]
    end

    test "lowers a comparison with an attribute" do
      assert lower_condition("owner_id == assignee_id") ==
               [owner_id: {:==, {:attribute, :assignee_id}}]
    end

    test "lowers a comparison with user_id()" do
      assert lower_condition("owner_id == user_id()") == [owner_id: {:==, {:actor}}]
    end

    test "lowers a conjunction with user_id()" do
      assert lower_condition("author_id == user_id() and archived == false") ==
               [author_id: {:==, {:actor}}, archived: {:==, false}]
    end

    test "lowers a disjunction with user_id()" do
      assert lower_condition("author_id == user_id() or shared == true") ==
               [or: [[author_id: {:==, {:actor}}], [shared: {:==, true}]]]
    end

    test "lowers a membership in a range" do
      assert lower_condition("count in 1..10") == [count: {:in, 1..10}]
    end

    test "lowers a negated membership" do
      assert lower_condition("status not in [:done]") == [status: {:not_in, [:done]}]
    end

    test "lowers a path compared with user_id()" do
      assert lower_condition("project.owner_id == user_id()") ==
               [{[:project, :owner_id], {:==, {:actor}}}]
    end

    test "lowers a pinned value" do
      assert lower_condition("priority < ^max", max: 3) == [priority: {:<, 3}]
    end

    test "lowers an inequality with user_id()" do
      assert lower_condition("owner_id != user_id()") == [owner_id: {:!=, {:actor}}]
    end

    test "lowers an ordering comparison with user_id()" do
      assert lower_condition("priority < user_id()") == [priority: {:<, {:actor}}]
    end

    test "lowers each comparison operator with an attribute" do
      assert lower_condition("guests == capacity") == [guests: {:==, {:attribute, :capacity}}]
      assert lower_condition("guests != capacity") == [guests: {:!=, {:attribute, :capacity}}]
      assert lower_condition("guests < capacity") == [guests: {:<, {:attribute, :capacity}}]
      assert lower_condition("guests <= capacity") == [guests: {:<=, {:attribute, :capacity}}]
      assert lower_condition("guests > capacity") == [guests: {:>, {:attribute, :capacity}}]
      assert lower_condition("guests >= capacity") == [guests: {:>=, {:attribute, :capacity}}]
    end

    test "passes a pinned predicates list through" do
      assert lower_condition("^predicates", predicates: [priority: {:>=, 3}]) ==
               [priority: {:>=, 3}]
    end

    test "raises on a bare name alone" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a condition: done - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, or a pinned list of predicates",
                   fn -> lower_condition("done") end
    end

    test "raises on a call as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path, user_id() or a pinned expression, got: Date.utc_today() - a value from the surrounding code is pinned: ^Date.utc_today()",
                   fn -> lower_condition("created_at > Date.utc_today()") end
    end

    test "raises on a keyword list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [shared: true] - write it as an expression: shared == true",
                   fn -> lower_condition("[shared: true]") end
    end

    test "raises on a keyword list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [a: 1] - write it as an expression: a == 1",
                   fn -> lower_condition("[a: 1] and b == 2") end
    end

    test "raises on a keyword list as a side of or" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [a: 1] - write it as an expression: a == 1",
                   fn -> lower_condition("[a: 1] or b == 2") end
    end

    test "raises on a keyword list holding a non-equality value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [priority: {:>=, 3}]",
                   fn -> lower_condition("[priority: {:>=, 3}]") end
    end

    test "raises on a keyword list of several entries" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [shared: true, status: :published] - write it as an expression: shared == true and status == :published",
                   fn -> lower_condition("[shared: true, status: :published]") end
    end

    test "raises on a keyword list with a pinned value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [owner_id: ^owner_id] - write it as an expression: owner_id == ^owner_id",
                   fn -> lower_condition("[owner_id: ^owner_id]") end
    end

    test "raises on a keyword list with user_id()" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [owner_id: user_id()] - write it as an expression: owner_id == user_id()",
                   fn -> lower_condition("[owner_id: user_id()]") end
    end

    test "raises on a pinned list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a pinned list of predicates is a whole condition, not one side of and, got: ^base - put the other comparisons in the list",
                   fn -> lower_condition("^base and b == 2") end
    end

    test "raises on a pinned list as a side of or" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a pinned list of predicates is a whole condition, not one side of or, got: ^base - put the whole disjunction in the list: [or: [predicates, predicates]]",
                   fn -> lower_condition("^base or b == 2") end
    end

    test "raises on a quantifier" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a condition: any(member <- members, member.user_id == user_id()) - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, or a pinned list of predicates",
                   fn ->
                     lower_condition("any(member <- members, member.user_id == user_id())")
                   end
    end

    test "raises on nil" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: unsupported expression in a condition: nil - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, or a pinned list of predicates",
                   fn -> lower_condition("nil") end
    end

    test "raises on paren-less user_id" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: paren-less user_id - did you mean user_id()?",
                   fn -> lower_condition("owner_id == user_id") end
    end

    test "raises on true" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: unsupported expression in a condition: true - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, or a pinned list of predicates",
                   fn -> lower_condition("true") end
    end

    test "raises on user_id() as the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the entity or a path to one, got: user_id()",
                   fn -> lower_condition("user_id() == owner_id") end
    end
  end

  describe "hops/1" do
    test "returns a bare name as one hop" do
      assert hops(Code.string_to_quoted!("owner")) == [:owner]
    end

    test "returns nil for a call" do
      assert hops(Code.string_to_quoted!("tasks.owner()")) == nil
    end

    test "returns nil for a chain over __MODULE__" do
      assert hops(Code.string_to_quoted!("__MODULE__.tasks")) == nil
    end

    test "returns the hops of a path" do
      assert hops(Code.string_to_quoted!("project.tasks.owner")) == [:project, :tasks, :owner]
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

    test "raises on a path over __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__.tasks() - a value from the surrounding code is pinned: ^__MODULE__.tasks()",
                   fn -> lower_inclusion("__MODULE__.tasks") end
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
                   "lib/my_app/queries.ex:12: sort names an attribute with a bare name, or with a pinned expression when the name comes from the surrounding code, got: sort_key() - a value from the surrounding code is pinned: ^sort_key()",
                   fn -> lower_ordering("sort_key()") end
    end

    test "raises on a dot path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: sort names an attribute with a bare name, or with a pinned expression when the name comes from the surrounding code, got: entity.field - a value from the surrounding code is pinned: ^entity.field",
                   fn -> lower_ordering("entity.field") end
    end

    test "raises on an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: sort names an attribute with a bare name, got: :priority - write priority",
                   fn -> lower_ordering(":priority") end
    end

    test "raises on an atom in a list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: sort names an attribute with a bare name, got: :created_at - write created_at",
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
    test "flattens a chain of disjunctions" do
      assert lower_predicates("a == 1 or b == 2 or c == 3") ==
               [or: [[a: {:==, 1}], [b: {:==, 2}], [c: {:==, 3}]]]
    end

    test "flattens a grouped disjunction inside a disjunction" do
      assert lower_predicates("a == 1 or (b == 2 or c == 3)") ==
               [or: [[a: {:==, 1}], [b: {:==, 2}], [c: {:==, 3}]]]
    end

    test "keeps a pinned keyword value an equality operand" do
      assert lower_predicates("[status: ^statuses]", statuses: [:todo]) ==
               [status: {:==, [:todo]}]
    end

    test "lowers a bound row's path inside a quantifier" do
      assert lower_predicates(~s|any(message <- messages, message.author.name == "ada")|) ==
               [any: {[:messages], [{[:author, :name], {:==, "ada"}}]}]
    end

    test "lowers a comparison between two paths" do
      assert lower_predicates("trip.starts_on < trip.ends_on") ==
               [{[:trip, :starts_on], {:<, {:attribute, [:trip, :ends_on]}}}]
    end

    test "lowers a comparison with a module name" do
      assert lower_predicates("entity_type == MyApp.Trip") == [entity_type: {:==, MyApp.Trip}]
    end

    test "lowers a comparison with a negative number" do
      assert lower_predicates("priority > -7") == [priority: {:>, -7}]
    end

    test "lowers a comparison with a path as the operand" do
      assert lower_predicates("starts_on < trip.ends_on") ==
               [starts_on: {:<, {:attribute, [:trip, :ends_on]}}]
    end

    test "lowers a comparison with a path on the left" do
      assert lower_predicates("channel.archived == false") ==
               [{[:channel, :archived], {:==, false}}]
    end

    test "lowers a comparison with an attribute" do
      assert lower_predicates("end_date < start_date") ==
               [end_date: {:<, {:attribute, :start_date}}]
    end

    test "lowers a comparison with nil" do
      assert lower_predicates("archived_at == nil") == [archived_at: {:==, nil}]
    end

    test "lowers a condition reading a row bound around it" do
      assert lower_predicates(
               "any(channel <- channels, any(message <- channel.messages, message.created_at > channel.archived_at))"
             ) ==
               [
                 any:
                   {[:channels],
                    [
                      any:
                        {[:messages], [created_at: {:>, {:attribute, {:outer, 1, :archived_at}}}]}
                    ]}
               ]
    end

    test "lowers a condition reading the queried row two quantifiers out" do
      assert lower_predicates(
               "any(channel <- channels, any(message <- channel.messages, message.body == name))"
             ) ==
               [
                 any:
                   {[:channels],
                    [any: {[:messages], [body: {:==, {:attribute, {:outer, 2, :name}}}]}]}
               ]
    end

    test "lowers a conjunction of three predicates" do
      assert lower_predicates(~s(a == true and b > 1 and c != "x")) ==
               [a: {:==, true}, b: {:>, 1}, c: {:!=, "x"}]
    end

    test "lowers a disjunction" do
      assert lower_predicates("a == 1 or b == 2") == [or: [[a: {:==, 1}], [b: {:==, 2}]]]
    end

    test "lowers a disjunction inside a quantifier's condition" do
      assert lower_predicates(
               ~s|any(message <- messages, message.body == "a" or message.position > 3)|
             ) == [any: {[:messages], [or: [[body: {:==, "a"}], [position: {:>, 3}]]]}]
    end

    test "lowers a disjunction nested inside an alternative" do
      assert lower_predicates("a == 1 or (b == 2 and (c == 3 or d == 4))") ==
               [or: [[a: {:==, 1}], [b: {:==, 2}, or: [[c: {:==, 3}], [d: {:==, 4}]]]]]
    end

    test "lowers a disjunction of conjunctions, and binding tighter" do
      assert lower_predicates("a == 1 and b == 2 or c == 3") ==
               [or: [[a: {:==, 1}, b: {:==, 2}], [c: {:==, 3}]]]
    end

    test "lowers a grouped disjunction inside a conjunction" do
      assert lower_predicates("a == 1 and (b == 2 or c == 3)") ==
               [a: {:==, 1}, or: [[b: {:==, 2}], [c: {:==, 3}]]]
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

    test "lowers a membership and a pinned value as alternatives" do
      assert lower_predicates("status in [:todo, :doing] or owner_id == ^owner_id", owner_id: "u") ==
               [or: [[status: {:in, [:todo, :doing]}], [owner_id: {:==, "u"}]]]
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

    test "lowers a membership inside a quantifier's condition" do
      assert lower_predicates("any(message <- messages, message.position in [1, ^p])", p: 2) ==
               [any: {[:messages], [position: {:in, [1, 2]}]}]
    end

    test "lowers a membership on a path" do
      assert lower_predicates("channel.kind in [:dm, :group]") ==
               [{[:channel, :kind], {:in, [:dm, :group]}}]
    end

    test "lowers a negated membership" do
      assert lower_predicates("status not in [:done]") == [status: {:not_in, [:done]}]
    end

    test "lowers a negated membership in a pinned list" do
      assert lower_predicates("status not in ^statuses", statuses: [:done]) ==
               [status: {:not_in, [:done]}]
    end

    test "lowers a path inside a disjunction" do
      assert lower_predicates("channel.archived == false or pinned == true") ==
               [or: [[{[:channel, :archived], {:==, false}}], [pinned: {:==, true}]]]
    end

    test "lowers a path of the queried row inside a quantifier's condition" do
      assert lower_predicates("any(message <- messages, message.body == channel.org.name)") ==
               [
                 any:
                   {[:messages],
                    [body: {:==, {:attribute, {:outer, 1, [:channel, :org, :name]}}}]}
               ]
    end

    test "lowers a pinned call" do
      assert lower_predicates("created_at > ^Date.add(today, -7)", today: ~D[2026-10-20]) ==
               [created_at: {:>, ~D[2026-10-13]}]
    end

    test "lowers a pinned dot chain" do
      assert lower_predicates("author_id == ^user.id", user: %{id: "u"}) ==
               [author_id: {:==, "u"}]
    end

    test "lowers a quantifier as a side of and" do
      assert lower_predicates("archived == false and any(messages)") ==
               [archived: {:==, false}, any: {[:messages], []}]
    end

    test "lowers a quantifier as an alternative" do
      assert lower_predicates(
               "deleted_at == nil or (thread.message_id == id and any(reply <- thread.messages, reply.id != id))"
             ) ==
               [
                 or: [
                   [deleted_at: {:==, nil}],
                   [
                     {[:thread, :message_id], {:==, {:attribute, :id}}},
                     {:any, {[:thread, :messages], [id: {:!=, {:attribute, {:outer, 1, :id}}}]}}
                   ]
                 ]
               ]
    end

    test "lowers a quantifier over a path's relationship" do
      assert lower_predicates(
               "any(message <- channel.messages, message.created_at > last_read_at)"
             ) ==
               [
                 any:
                   {[:channel, :messages],
                    [created_at: {:>, {:attribute, {:outer, 1, :last_read_at}}}]}
               ]
    end

    test "lowers a quantifier with a condition" do
      assert lower_predicates("any(message <- messages, message.author_id == ^user_id)",
               user_id: "u1"
             ) == [any: {[:messages], [author_id: {:==, "u1"}]}]
    end

    test "lowers a quantifier with no condition" do
      assert lower_predicates("none(messages)") == [none: {[:messages], []}]
    end

    test "lowers a quantifier's relationship read on a row bound two quantifiers out" do
      assert lower_predicates("any(a <- as, any(b <- a.bs, any(c <- a.cs, c.x == b.y)))") ==
               [
                 any:
                   {[:as],
                    [
                      any:
                        {[:bs],
                         [any: {{:outer, 1, [:cs]}, [x: {:==, {:attribute, {:outer, 1, :y}}}]}]}
                    ]}
               ]
    end

    test "lowers a quantifier's relationship read on the queried row inside another quantifier" do
      assert lower_predicates(
               "any(channel <- channels, any(message <- messages, message.body == channel.name))"
             ) ==
               [
                 any:
                   {[:channels],
                    [
                      any:
                        {{:outer, 1, [:messages]},
                         [body: {:==, {:attribute, {:outer, 1, :name}}}]}
                    ]}
               ]
    end

    test "lowers a two-hop path" do
      assert lower_predicates("channel.org.name == ^org_name", org_name: "acme") ==
               [{[:channel, :org, :name], {:==, "acme"}}]
    end

    test "lowers all and none with a condition" do
      assert lower_predicates(
               "all(task <- tasks, task.done == true) and none(task <- tasks, task.late == true)"
             ) == [all: {[:tasks], [done: {:==, true}]}, none: {[:tasks], [late: {:==, true}]}]
    end

    test "lowers an attribute comparison inside a disjunction" do
      assert lower_predicates("end_date < start_date or shared == true") ==
               [or: [[end_date: {:<, {:attribute, :start_date}}], [shared: {:==, true}]]]
    end

    test "lowers an attribute of the queried row on the left inside a quantifier's condition" do
      assert lower_predicates("any(message <- messages, archived == false)") ==
               [any: {[:messages], [{{:outer, 1, :archived}, {:==, false}}]}]
    end

    test "lowers each comparison operator" do
      assert lower_predicates("b == 1") == [b: {:==, 1}]
      assert lower_predicates("b != 1") == [b: {:!=, 1}]
      assert lower_predicates("b < 1") == [b: {:<, 1}]
      assert lower_predicates("b <= 1") == [b: {:<=, 1}]
      assert lower_predicates("b > 1") == [b: {:>, 1}]
      assert lower_predicates("b >= 1") == [b: {:>=, 1}]
    end

    test "lowers each comparison operator with an attribute" do
      assert lower_predicates("b == c") == [b: {:==, {:attribute, :c}}]
      assert lower_predicates("b != c") == [b: {:!=, {:attribute, :c}}]
      assert lower_predicates("b < c") == [b: {:<, {:attribute, :c}}]
      assert lower_predicates("b <= c") == [b: {:<=, {:attribute, :c}}]
      assert lower_predicates("b > c") == [b: {:>, {:attribute, :c}}]
      assert lower_predicates("b >= c") == [b: {:>=, {:attribute, :c}}]
    end

    test "passes a pinned predicates list through" do
      assert lower_predicates("^predicates", predicates: [priority: {:>=, 3}]) ==
               [priority: {:>=, 3}]
    end

    test "raises on __DIR__ as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: __DIR__ - a value from the surrounding code is pinned: ^__DIR__",
                   fn -> lower_predicates("path == __DIR__") end
    end

    test "raises on __MODULE__ as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: __MODULE__ - a value from the surrounding code is pinned: ^__MODULE__",
                   fn -> lower_predicates("entity_type == __MODULE__") end
    end

    test "raises on __MODULE__ as the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: __MODULE__",
                   fn -> lower_predicates("__MODULE__ == entity_type") end
    end

    test "raises on a bare name alone" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("done") end
    end

    test "raises on a bare name as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: assignee_id reads as an attribute of the queried entity, and a keyword predicate value is a literal or a pinned expression - a value from the surrounding code is pinned: ^assignee_id, and a comparison with an attribute is written as an expression: owner_id == assignee_id",
                   fn -> lower_predicates("[owner_id: assignee_id]") end
    end

    test "raises on a bare name as a keyword value named after its key" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: project_id reads as an attribute of the queried entity, and a keyword predicate value is a literal or a pinned expression - a value from the surrounding code is pinned: ^project_id",
                   fn -> lower_predicates("[project_id: project_id]") end
    end

    test "raises on a bare name as a membership element" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: other reads as an attribute of the queried entity, and a membership element is a literal or a pinned expression - a value from the surrounding code is pinned: ^other",
                   fn -> lower_predicates("status in [other]") end
    end

    test "raises on a bare name as a membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a membership operand is a list, a range or a pinned expression, got: statuses - a value from the surrounding code is pinned: ^statuses",
                   fn -> lower_predicates("status in statuses") end
    end

    test "raises on a bare name as a range bound" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: high reads as an attribute of the queried entity, and a range bound is a literal or a pinned expression - a value from the surrounding code is pinned: ^high",
                   fn -> lower_predicates("n in 1..high") end
    end

    test "raises on a bound name bound again by a nested quantifier, at the nested binding" do
      code = """
      any(message <- messages,
        any(message <- message.replies, message.body == "x"))
      """

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:13: message is already bound by an enclosing quantifier - name this row differently",
                   fn -> lower_predicates(code) end
    end

    test "raises on a bound row as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: message is a bound row - compare one of its attributes: message.<attribute>",
                   fn -> lower_predicates("any(message <- messages, message.x == message)") end
    end

    test "raises on a bound row as a quantifier's relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: message is a bound row - a quantifier's source is a relationship: message.<relationship>",
                   fn ->
                     lower_predicates(
                       "any(message <- messages, any(reply <- message, reply.x == 1))"
                     )
                   end
    end

    test "raises on a bound row compared whole, at the bound row" do
      code = """
      any(message <- messages,
        message == pinned)
      """

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:13: message is a bound row - compare one of its attributes: message.<attribute>",
                   fn -> lower_predicates(code) end
    end

    test "raises on a call as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: Date.utc_today() - a value from the surrounding code is pinned: ^Date.utc_today()",
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
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: open_predicates() - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("open_predicates()") end
    end

    test "raises on a call on the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: channel.archived()",
                   fn -> lower_predicates("channel.archived() == false") end
    end

    test "raises on a dot chain over __MODULE__ as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: __MODULE__.type() - a value from the surrounding code is pinned: ^__MODULE__.type()",
                   fn -> lower_predicates("entity_type == __MODULE__.type") end
    end

    test "raises on a dot chain over __MODULE__ as the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: __MODULE__.type()",
                   fn -> lower_predicates("__MODULE__.type == 1") end
    end

    test "raises on a keyword list as a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's condition is an expression, got: [author_id: 1] - a filter built at runtime goes whole into filter(^predicates)",
                   fn -> lower_predicates("any(message <- messages, author_id: 1)") end
    end

    test "raises on a keyword list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword list or a pinned list of predicates is a whole filter, not one side of and, got: [a: 1] - pass it to a filter call of its own",
                   fn -> lower_predicates("[a: 1] and b == 2") end
    end

    test "raises on a keyword list as a side of or" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword list or a pinned list of predicates is a whole filter, not one side of or, got: [a: 1] - write the alternative as an expression, or put the whole disjunction in a pinned list: [or: [predicates, predicates]]",
                   fn -> lower_predicates("[a: 1] or b == 2") end
    end

    test "raises on a list as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: [:todo, :doing]] - write it as an expression: status in [:todo, :doing]",
                   fn -> lower_predicates("[status: [:todo, :doing]]") end
    end

    test "raises on a literal binding, at the quantifier" do
      code = """
      body == "x" and
        any(1 <- messages, x == 1)
      """

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:13: a quantifier binds its related row to a bare name, got: 1",
                   fn -> lower_predicates(code) end
    end

    test "raises on a membership tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:in, [:todo]}] - write it as an expression: status in [:todo]",
                   fn -> lower_predicates("[status: {:in, [:todo]}]") end
    end

    test "raises on a module attribute as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: @max - a value from the surrounding code is pinned: ^@max",
                   fn -> lower_predicates("priority < @max") end
    end

    test "raises on a negated disjunction" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: not (a == 1 or b == 2) - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("not (a == 1 or b == 2)") end
    end

    test "raises on a negated membership tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:not_in, [:done]}] - write it as an expression: status not in [:done]",
                   fn -> lower_predicates("[status: {:not_in, [:done]}]") end
    end

    test "raises on a negation that is not a membership" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: not done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("not done") end
    end

    test "raises on a non-atom keyword key" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate names an attribute with an atom, got: {key, 1}",
                   fn -> lower_predicates("[{key, 1}]") end
    end

    test "raises on a path as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: channel.id reads as a path through the queried entity, and a keyword predicate value is a literal or a pinned expression - a value from the surrounding code is pinned: ^channel.id, and a comparison with a path is written as an expression: channel_id == channel.id",
                   fn -> lower_predicates("[channel_id: channel.id]") end
    end

    test "raises on a path as a membership element" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a membership element is a literal or a pinned expression, got: channel.status - a value from the surrounding code is pinned: ^channel.status",
                   fn -> lower_predicates("status in [channel.status]") end
    end

    test "raises on a pinned left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: ^x",
                   fn -> lower_predicates("^x == a") end
    end

    test "raises on a pinned list as a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's condition is an expression, got: ^predicates - a filter built at runtime goes whole into filter(^predicates)",
                   fn -> lower_predicates("any(message <- messages, ^predicates)") end
    end

    test "raises on a pinned list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword list or a pinned list of predicates is a whole filter, not one side of and, got: ^predicates - pass it to a filter call of its own",
                   fn -> lower_predicates("^predicates and b == 2") end
    end

    test "raises on a pinned list as a side of and inside a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's condition is an expression, got: ^predicates - a filter built at runtime goes whole into filter(^predicates)",
                   fn ->
                     lower_predicates("any(message <- messages, message.x == 1 and ^predicates)")
                   end
    end

    test "raises on a pinned list as a side of or" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword list or a pinned list of predicates is a whole filter, not one side of or, got: ^base - write the alternative as an expression, or put the whole disjunction in a pinned list: [or: [predicates, predicates]]",
                   fn -> lower_predicates("^base or b == 2") end
    end

    test "raises on a pinned quantifier's relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's source is a relationship written in place, got: ^relationship",
                   fn -> lower_predicates("any(message <- ^relationship, message.x == 1)") end
    end

    test "raises on a pinned quantifier's relationship with a binding and no condition, judging the relationship first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's source is a relationship written in place, got: ^relationship",
                   fn -> lower_predicates("any(message <- ^relationship)") end
    end

    test "raises on a pinned quantifier's relationship with no condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's source is a relationship written in place, got: ^relationship",
                   fn -> lower_predicates("any(^relationship)") end
    end

    test "raises on a quantifier binding a row no condition reads" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: any(message <- messages) binds a row no condition reads - write any(messages)",
                   fn -> lower_predicates("any(message <- messages)") end
    end

    test "raises on a quantifier binding something other than a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier binds its related row to a bare name, got: __MODULE__",
                   fn -> lower_predicates("any(__MODULE__ <- messages, x == 1)") end
    end

    test "raises on a quantifier over something other than a relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's source is a relationship or a path to one, got: messages()",
                   fn -> lower_predicates("any(messages())") end
    end

    test "raises on a quantifier with a condition and no bound row" do
      assert_error Hologram.CompileError,
                   ~s|lib/my_app/queries.ex:12: a quantifier binds the related row its condition reads, got: any(messages, body == "x") - write any(row <- messages, ...) and read the row as row.<attribute>|,
                   fn -> lower_predicates(~s|any(messages, body == "x")|) end
    end

    test "raises on a quantifier with no arguments" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: none takes a relationship, or a row bound to one and a condition - none(messages), none(message <- messages, message.author_id == ^user_id) - got: none()",
                   fn -> lower_predicates("none()") end
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
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: ~D[2026-01-01] - a value from the surrounding code is pinned: ^~D[2026-01-01]",
                   fn -> lower_predicates("created_at > ~D[2026-01-01]") end
    end

    test "raises on a tuple naming no operator as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:foo, 1}] - a comparison, a membership or a range is written as an expression",
                   fn -> lower_predicates("[status: {:foo, 1}]") end
    end

    test "raises on a value on the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: the left side of a comparison names an attribute of the queried entity or a path to one, got: 3",
                   fn -> lower_predicates("3 <= priority") end
    end

    test "raises on all with a bound row and no condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: all takes a condition - all over no condition says nothing, got: all(task <- tasks) - write all(task <- tasks, task.<attribute> == ...)",
                   fn -> lower_predicates("all(task <- tasks)") end
    end

    test "raises on all with no arguments, naming the spelling all takes" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: all takes a row bound to a relationship and a condition - all(task <- tasks, task.done == true) - got: all()",
                   fn -> lower_predicates("all()") end
    end

    test "raises on all with no condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: all takes a condition - all over no condition says nothing, got: all(tasks) - write all(row <- tasks, row.<attribute> == ...)",
                   fn -> lower_predicates("all(tasks)") end
    end

    test "raises on an operator expression as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: n * 2 - a value from the surrounding code is pinned: ^(n * 2)",
                   fn -> lower_predicates("b > n * 2") end
    end

    test "raises on an operator tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [priority: {:>=, 3}] - write it as an expression: priority >= 3",
                   fn -> lower_predicates("[priority: {:>=, 3}]") end
    end

    test "raises on comparisons listed instead of joined" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a keyword predicate is attribute: value, got: a == 1 - join comparisons with and",
                   fn -> lower_predicates("[a == 1, b == 2]") end
    end

    test "raises on user_id() as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: user_id() - a value from the surrounding code is pinned: ^user_id()",
                   fn -> lower_predicates("owner_id == user_id()") end
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
