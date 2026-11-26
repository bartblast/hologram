defmodule Hologram.Query.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Expression

  # The code is parsed at line 12 of a stage call made at line 7, so a refusal located at a node
  # names line 12 and one located at a node carrying no line (a literal) names the call's line.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/queries.ex"), line: 7}
  end

  # Lowers predicates where the macro is called, returning what they lowered to as data.
  defmacro lower_in_caller(ast) do
    ast
    |> predicates(__CALLER__)
    |> Macro.escape()
  end

  # The env of a stage call made where variables of the given names are bound.
  defp env_binding(names) do
    assignments =
      names
      |> List.wrap()
      |> Enum.map(&{:=, [], [{&1, [], nil}, nil]})

    {_value, _binding, env} =
      Code.eval_quoted_with_env({:__block__, [], [nil | assignments]}, [], env())

    env
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

  # The hints of the given code, where variables of the given names are bound - the names in marked
  # being a derived field's arguments, marked the way DerivedExpression marks them.
  defp hints_of(hinting, code, names, marked \\ []) do
    code
    |> Code.string_to_quoted!(line: 12)
    |> Macro.prewalk(fn
      {name, _meta, context} = ast when is_atom(name) and is_atom(context) ->
        if name in marked, do: mark_pinnable(ast), else: ast

      ast ->
        ast
    end)
    |> hinting.(env_binding(names))
  end

  # The stage call is made where the binding's variables are bound, as a pinned name reads one.
  defp lower_bound(code, binding \\ []),
    do: lower(&bound(&1, :take, env_binding(Keyword.keys(binding))), code, binding)

  defp lower_condition(code, binding \\ []),
    do: lower(&condition(&1, env_binding(Keyword.keys(binding))), code, binding)

  defp lower_inclusion(code, binding \\ []),
    do: lower(&inclusion(&1, env_binding(Keyword.keys(binding))), code, binding)

  defp lower_ordering(code, binding \\ []),
    do: lower(&ordering(&1, env_binding(Keyword.keys(binding))), code, binding)

  defp lower_pagination(code, binding \\ []),
    do: lower(&pagination(&1, env_binding(Keyword.keys(binding))), code, binding)

  defp lower_predicates(code, binding \\ []),
    do: lower(&predicates(&1, env_binding(Keyword.keys(binding))), code, binding)

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

  describe "condition_hints/2" do
    test "spells a name inside a quantifier on each row" do
      assert hints_of(&condition_hints/2, "any(member <- members, user_id == user_id())", []) == [
               {:key, 1, {:outer, 1, :user_id}, nil, ["member.user_id", "user_id"]}
             ]
    end

    test "hints nothing at the top of a condition naming no variable" do
      assert hints_of(&condition_hints/2, "owner_id == assignee_id and status in [:open]", []) ==
               []
    end

    test "hints nothing for pinned predicates" do
      assert hints_of(&condition_hints/2, "^predicates", [:predicates]) == []
    end
  end

  describe "condition/2" do
    test "names a backfill word on the left side of a comparison" do
      assert_error Hologram.CompileError,
                   ~s[lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the entity or a path to one, got: coalesce(a, b) - if you meant the query word coalesce, it works only in a migration's backfill: for now],
                   fn -> lower_condition(~s[coalesce(a, b) == "x"]) end
    end

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

    test "lowers a nested quantifier reading the rule's row two quantifiers out" do
      assert lower_condition(
               "any(member <- members, any(label <- member.labels, label.name == name))"
             ) ==
               [
                 any:
                   {[:members],
                    [any: {[:labels], [name: {:==, {:attribute, {:outer, 2, :name}}}]}]}
               ]
    end

    test "lowers a path compared with user_id()" do
      assert lower_condition("project.owner_id == user_id()") ==
               [{[:project, :owner_id], {:==, {:actor}}}]
    end

    test "lowers a pinned value" do
      assert lower_condition("priority < ^max", max: 3) == [priority: {:<, 3}]
    end

    test "lowers a pinned value inside a quantifier's condition" do
      assert lower_condition("any(member <- members, member.seat == ^seat)", seat: "full") ==
               [any: {[:members], [seat: {:==, "full"}]}]
    end

    test "lowers a quantifier as an alternative beside user_id()" do
      assert lower_condition(
               "owner_id == user_id() or any(member <- members, member.user_id == user_id())"
             ) ==
               [
                 or: [
                   [owner_id: {:==, {:actor}}],
                   [any: {[:members], [user_id: {:==, {:actor}}]}]
                 ]
               ]
    end

    test "lowers a quantifier comparing a related row with user_id()" do
      assert lower_condition("any(member <- members, member.user_id == user_id())") ==
               [any: {[:members], [user_id: {:==, {:actor}}]}]
    end

    test "lowers a quantifier over a path's relationship with no condition" do
      assert lower_condition("none(project.members)") == [none: {[:project, :members], []}]
    end

    test "lowers a quantifier's relationship read on the rule's row inside another quantifier" do
      assert lower_condition("none(label <- project.labels, any(project.members))") ==
               [none: {[:project, :labels], [any: {{:outer, 1, [:project, :members]}, []}]}]
    end

    test "lowers a search" do
      assert lower_condition(~s|starts_with(path, "public/", mode: :exact)|) ==
               [path: {:starts_with_exact, "public/"}]
    end

    test "lowers all and none with a condition" do
      assert lower_condition("all(task <- tasks, task.done == true)") ==
               [all: {[:tasks], [done: {:==, true}]}]

      assert lower_condition("none(task <- tasks, task.done == false)") ==
               [none: {[:tasks], [done: {:==, false}]}]
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

    test "raises on String.starts_with?/2" do
      assert_error Hologram.CompileError,
                   ~s|lib/my_app/queries.ex:12: String.starts_with?/2 isn't available in a condition - write starts_with(path, "public/"), which ignores case and accents, or starts_with(path, "public/", mode: :exact) to match byte for byte|,
                   fn -> lower_condition(~s|String.starts_with?(path, "public/")|) end
    end

    test "raises on a bare name alone" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a condition: done - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), or a pinned list of predicates",
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

    test "raises on a keyword list as a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's condition is an expression, got: [user_id: 1] - a condition built at runtime goes whole into when: ^predicates",
                   fn -> lower_condition("any(member <- members, user_id: 1)") end
    end

    test "raises on a keyword list as a side of and" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a condition is an expression, got: [a: 1] - write it as an expression: a == 1",
                   fn -> lower_condition("[a: 1] and b == 2") end
    end

    test "raises on a keyword list as a side of and inside a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a quantifier's condition is an expression, got: [seat: \"full\"] - a condition built at runtime goes whole into when: ^predicates",
                   fn ->
                     lower_condition("any(member <- members, member.a == 1 and [seat: \"full\"])")
                   end
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

    test "raises on a pinned name no variable holds, naming the field of the entity" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^owner_id pins owner_id, which no variable holds here - inside a condition a name without a pin reads a field of the entity: owner_id",
                   fn -> lower_condition("assignee_id == ^owner_id") end
    end

    test "raises on a pinned name no variable holds inside a quantifier's condition, naming the bound row too" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^role pins role, which no variable holds here - inside a condition a name without a pin reads a field of the entity: role - or of the row member binds, through its name: member.role",
                   fn -> lower_condition("any(member <- members, member.role == ^role)") end
    end

    test "raises on a pinned quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's condition is an expression, got: ^predicates - a condition built at runtime goes whole into when: ^predicates",
                   fn -> lower_condition("any(member <- members, ^predicates)") end
    end

    test "raises on a pinned user_id no variable holds, naming user_id()" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^user_id pins user_id, which no variable holds here - the acting user's id is user_id()",
                   fn -> lower_condition("owner_id == ^user_id") end
    end

    test "raises on a quantifier with too many arguments, naming user_id()" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: any takes a relationship, or a row bound to one and a condition - any(messages), any(message <- messages, message.author_id == user_id()) - got: any(member <- members, member.a == 1, 2)",
                   fn -> lower_condition("any(member <- members, member.a == 1, 2)") end
    end

    test "raises on all with no condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: all takes a condition - all over no condition says nothing, got: all(members) - write all(row <- members, row.<attribute> == ...)",
                   fn -> lower_condition("all(members)") end
    end

    test "raises on an attribute compared with itself" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: owner_id == owner_id compares owner_id with itself, which is always true",
                   fn -> lower_condition("owner_id == owner_id") end
    end

    test "raises on an attribute compared with itself beside a variable of its name, naming the pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: owner_id == owner_id compares owner_id with itself, which is always true - a value from the surrounding code is pinned: ^owner_id",
                   fn -> lower(&condition(&1, env_binding(:owner_id)), "owner_id == owner_id") end
    end

    test "raises on an attribute compared with itself inside a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: member.role >= member.role compares member.role with itself, which only says member.role isn't nil - write member.role != nil",
                   fn ->
                     lower_condition("any(member <- members, member.role >= member.role)")
                   end
    end

    test "raises on new() when the line has no row after a change" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(status)",
                   fn -> lower_condition("new(status) == :approved") end
    end

    test "raises on nil" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: unsupported expression in a condition: nil - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), or a pinned list of predicates",
                   fn -> lower_condition("nil") end
    end

    test "raises on paren-less user_id" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: paren-less user_id - did you mean user_id()?",
                   fn -> lower_condition("owner_id == user_id") end
    end

    test "raises on paren-less user_id inside a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: paren-less user_id - did you mean user_id()?",
                   fn -> lower_condition("any(member <- members, member.user_id == user_id)") end
    end

    test "raises on true" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: unsupported expression in a condition: true - a condition is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), or a pinned list of predicates",
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
    test "doesn't name a backfill word, which could never go here" do
      error =
        assert_raise Hologram.CompileError, fn ->
          lower_inclusion(~s[split(a, ",")])
        end

      refute Exception.message(error) =~ "query word"
    end

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

    test "lowers a list of names and paths" do
      assert lower_inclusion("[owner, tasks.owner]") == [:owner, tasks: [:owner]]
    end

    test "lowers a path" do
      assert lower_inclusion("tasks.owner") == [tasks: [:owner]]
    end

    test "lowers a three-hop path" do
      assert lower_inclusion("a.b.c") == [a: [b: [:c]]]
    end

    test "lowers a keyword entry with a pinned nested spec" do
      assert lower_inclusion("[tasks: ^nested]", nested: [:owner]) == [tasks: [:owner]]
    end

    test "merges paths sharing a first hop in the order it first appears" do
      assert lower_inclusion("[tasks.owner, owner, tasks.project]") ==
               [{:tasks, [:owner, :project]}, :owner]
    end

    test "merges paths sharing two hops" do
      assert lower_inclusion("[a.b.c, a.b.d]") == [a: [b: [:c, :d]]]
    end

    test "passes a pinned path over a variable through" do
      assert lower_inclusion("^opts.relationship", opts: %{relationship: :owner}) == :owner
    end

    test "passes a pinned spec through" do
      assert lower_inclusion("^spec", spec: [project: [:owner]]) == [project: [:owner]]
    end

    # Elixir expands a name a macro marked if_undefined: :apply to a call of that name where no
    # variable holds it.
    test "passes a pinned name that falls back to a call through" do
      name = {:relationship, [if_undefined: :apply, line: 12], nil}

      assert inclusion({:^, [line: 12], [name]}, env()) == name
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

    test "raises on a keyword entry with a capture" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include takes names and paths, got: [tasks: &Function.identity/1] - a narrowed, ordered or bounded set is a derived field: derived :open_tasks, [Task], fn tasks -> filter(tasks, ...) end",
                   fn -> lower_inclusion("[tasks: &Function.identity/1]") end
    end

    test "raises on a keyword entry with an in-place fn" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include takes names and paths, got: [tasks: fn query -> query end] - a narrowed, ordered or bounded set is a derived field: derived :open_tasks, [Task], fn tasks -> filter(tasks, ...) end",
                   fn -> lower_inclusion("[tasks: fn query -> query end]") end
    end

    test "raises on a keyword entry with an unpinned call" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: include takes names and paths, got: [tasks: Foo.builder()] - a narrowed, ordered or bounded set is a derived field: derived :open_tasks, [Task], fn tasks -> filter(tasks, ...) end",
                   fn -> lower_inclusion("[tasks: Foo.builder()]") end
    end

    test "raises on a keyword entry with nil" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: include takes names and paths, got: [tasks: nil] - a narrowed, ordered or bounded set is a derived field: derived :open_tasks, [Task], fn tasks -> filter(tasks, ...) end",
                   fn -> lower_inclusion("[tasks: nil]") end
    end

    test "raises on a pinned element no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^owner pins owner, which no variable holds here - include names a relationship with a bare name or a path, without the pin: owner",
                   fn -> lower_inclusion("[tasks, ^owner]") end
    end

    test "raises on a pinned keyword entry no variable holds, naming the path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^owner pins owner, which no variable holds here - include names a relationship with a bare name or a path, without the pin: tasks.owner",
                   fn -> lower_inclusion("[tasks: ^owner]") end
    end

    test "raises on a pinned name no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^owner pins owner, which no variable holds here - include names a relationship with a bare name or a path, without the pin: owner",
                   fn -> lower_inclusion("^owner") end
    end

    test "raises on a pinned path no variable holds, naming the path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^tasks.owner pins tasks, which no variable holds here - include names a relationship with a bare name or a path, without the pin: tasks.owner",
                   fn -> lower_inclusion("^tasks.owner") end
    end

    test "raises on a pinned path in a keyword entry no variable holds, naming the path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^owner.project pins owner, which no variable holds here - include names a relationship with a bare name or a path, without the pin: tasks.owner.project",
                   fn -> lower_inclusion("[tasks: ^owner.project]") end
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

  describe "inclusion_hints/2" do
    @fix "a value from the surrounding code is pinned: ^relationship"

    test "hints the pin a variable's name forgot" do
      assert hints_of(&inclusion_hints/2, "relationship", [:relationship]) == [
               {:include, 0, :relationship, @fix, []}
             ]
    end

    test "hints the pin a variable's name forgot in a list" do
      assert hints_of(&inclusion_hints/2, "[owner, relationship, tasks.owner]", [:relationship]) ==
               [{:include, 0, :relationship, @fix, []}]
    end

    test "hints nothing for a path over a variable" do
      assert hints_of(&inclusion_hints/2, "relationship.owner", [:relationship]) == []
    end

    # Merged into the path, the name would still be read as a relationship once pinned.
    test "hints nothing for a variable's name a path in the list starts at" do
      assert hints_of(&inclusion_hints/2, "[relationship, relationship.owner]", [:relationship]) ==
               []
    end

    test "hints nothing for a name no variable holds" do
      assert hints_of(&inclusion_hints/2, "[owner, tasks]", []) == []
    end

    test "hints nothing for a keyword entry" do
      assert hints_of(&inclusion_hints/2, "[relationship: ^nested]", [:relationship, :nested]) ==
               []
    end

    test "hints nothing for a pinned spec" do
      assert hints_of(&inclusion_hints/2, "^relationship", [:relationship]) == []
    end

    # Pinned in a derived field's query, an argument is a field of the row, which an include can't
    # name.
    test "hints nothing for a derived field's argument" do
      assert hints_of(&inclusion_hints/2, "author", [], [:author]) == []
    end
  end

  describe "ordering/2" do
    test "names a backfill word as a sort's direction" do
      assert_error Hologram.CompileError, ~r/if you meant the query word coalesce/, fn ->
        lower_ordering(~s{[a: coalesce(b, "x")]})
      end
    end

    test "names a backfill word" do
      assert_error Hologram.CompileError,
                   ~r/sort names an attribute .* - if you meant the query word coalesce, it works only in a migration's backfill: for now$/,
                   fn -> lower_ordering(~s[coalesce(a, "x")]) end
    end

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

    # Elixir expands a name a macro marked if_undefined: :apply to a call of that name where no
    # variable holds it.
    test "passes a pinned name that falls back to a call through" do
      name = {:sort_key, [if_undefined: :apply, line: 12], nil}

      assert ordering({:^, [line: 12], [name]}, env()) == name
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

    test "raises on a pinned name in a pair no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^key pins key, which no variable holds here - sort names an attribute with a bare name, without the pin: key",
                   fn -> lower_ordering("[{^key, :desc}]") end
    end

    test "raises on a pinned name in a list no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^key pins key, which no variable holds here - sort names an attribute with a bare name, without the pin: key",
                   fn -> lower_ordering("[title, ^key]") end
    end

    test "raises on a pinned name no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^priority pins priority, which no variable holds here - sort names an attribute with a bare name, without the pin: priority",
                   fn -> lower_ordering("^priority") end
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

  describe "ordering_hints/2" do
    @fix "a value from the surrounding code is pinned: ^sort_field"

    test "hints the pin a variable's name forgot" do
      assert hints_of(&ordering_hints/2, "sort_field", [:sort_field]) == [
               {:sort, 0, :sort_field, @fix, []}
             ]
    end

    test "hints the pin a variable's name forgot in a list, paired or alone" do
      assert hints_of(&ordering_hints/2, "[{sort_field, :desc}, title, other]", [
               :sort_field,
               :other
             ]) == [
               {:sort, 0, :sort_field, @fix, []},
               {:sort, 0, :other, "a value from the surrounding code is pinned: ^other", []}
             ]
    end

    test "hints nothing for a name no variable holds" do
      assert hints_of(&ordering_hints/2, "[title, priority: :desc]", []) == []
    end

    test "hints nothing for a keyword key" do
      assert hints_of(&ordering_hints/2, "[sort_field: :desc]", [:sort_field]) == []
    end

    test "hints nothing for a pinned spec" do
      assert hints_of(&ordering_hints/2, "^sort_field", [:sort_field]) == []
    end

    # Pinned in a derived field's query, an argument is a field of the row, which a sort can't name.
    test "hints nothing for a derived field's argument" do
      assert hints_of(&ordering_hints/2, "position", [], [:position]) == []
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

  describe "predicate_hints/2" do
    @fix "a value from the surrounding code is pinned: ^search"

    test "hints the pin a variable's name forgot on the right side" do
      assert hints_of(&predicate_hints/2, "title == search", [:search]) == [
               {:operand, 0, :search, @fix, []}
             ]
    end

    test "hints the pin a path over a variable forgot" do
      assert hints_of(&predicate_hints/2, "owner_id == user.id", [:user]) == [
               {:operand, 0, [:user, :id],
                "a value from the surrounding code is pinned: ^user.id", []}
             ]
    end

    test "hints the pin a search term forgot" do
      assert hints_of(&predicate_hints/2, "contains(title, search, mode: :exact)", [:search]) ==
               [{:operand, 0, :search, @fix, []}]
    end

    test "hints a variable's name on the left side of a comparison with a name, flipping the operator" do
      assert hints_of(&predicate_hints/2, "search < title", [:search]) == [
               {:key, 0, :search,
                "a value from the surrounding code is pinned, on the right side: title > ^search",
                []}
             ]
    end

    test "hints a path over a variable on the left side of a comparison with a name" do
      assert hints_of(&predicate_hints/2, "user.name == title", [:user]) == [
               {:key, 0, [:user, :name],
                "a value from the surrounding code is pinned, on the right side: title == ^user.name",
                []}
             ]
    end

    test "hints a variable's name on the left side inside a quantifier, at its depth" do
      assert hints_of(
               &predicate_hints/2,
               "any(message <- messages, since <= message.created_at)",
               [:since]
             ) == [
               {:operand, 1, :created_at, nil, ["message.created_at", "created_at"]},
               {:key, 1, {:outer, 1, :since},
                "a value from the surrounding code is pinned, on the right side: message.created_at >= ^since",
                ["message.since", "since"]}
             ]
    end

    test "flips an ordering operator taking equality when it swaps the sides" do
      assert hints_of(&predicate_hints/2, "since >= created_at", [:since]) == [
               {:key, 0, :since,
                "a value from the surrounding code is pinned, on the right side: created_at <= ^since",
                []}
             ]
    end

    # The stage names the right side's fix first when that side is no attribute either.
    test "hints both sides when both are variables' names" do
      assert hints_of(&predicate_hints/2, "since < until", [:since, :until]) == [
               {:operand, 0, :until, "a value from the surrounding code is pinned: ^until", []},
               {:key, 0, :since,
                "a value from the surrounding code is pinned, on the right side: until > ^since",
                []}
             ]
    end

    test "hints nothing on the left side of a comparison with a pinned value" do
      assert hints_of(&predicate_hints/2, "project_id == ^project_id", [:project_id]) == []
    end

    test "hints nothing on the left side of a search" do
      assert hints_of(&predicate_hints/2, "contains(search, title)", [:search]) == []
    end

    test "hints the argument a derived field's query forgot to pin" do
      assert hints_of(&predicate_hints/2, "created_at > last_read_at", [], [:last_read_at]) == [
               {:operand, 0, :last_read_at,
                "last_read_at is an argument of the derived field's function, read pinned: ^last_read_at",
                []}
             ]
    end

    test "hints a derived field's argument on the left side of a comparison with a name" do
      assert hints_of(&predicate_hints/2, "last_read_at < created_at", [], [:last_read_at]) == [
               {:key, 0, :last_read_at,
                "last_read_at is an argument of the derived field's function, read pinned, on the right side: created_at > ^last_read_at",
                []}
             ]
    end

    test "hints the pin a variable's name forgot inside a quantifier, at its depth" do
      assert hints_of(
               &predicate_hints/2,
               "any(message <- messages, message.created_at > search)",
               [:search]
             ) == [
               {:operand, 1, {:outer, 1, :search}, @fix, ["message.search", "search"]},
               {:key, 1, :created_at, nil, ["message.created_at", "created_at"]}
             ]
    end

    test "spells a name inside nested quantifiers on each row, nearest first" do
      assert hints_of(
               &predicate_hints/2,
               "any(channel <- channels, any(message <- channel.messages, body == \"x\"))",
               []
             ) == [
               {:key, 2, {:outer, 2, :body}, nil, ["message.body", "channel.body", "body"]}
             ]
    end

    test "spells a membership's and a search's left side inside a quantifier" do
      assert hints_of(
               &predicate_hints/2,
               "any(message <- messages, position in [1, 2] and contains(body, \"x\"))",
               []
             ) == [
               {:key, 1, {:outer, 1, :position}, nil, ["message.position", "position"]},
               {:key, 1, {:outer, 1, :body}, nil, ["message.body", "body"]}
             ]
    end

    test "spells no bare name for the queried row where a quantifier binds that name" do
      assert hints_of(
               &predicate_hints/2,
               "any(role <- members, role.role == \"admin\")",
               []
             ) == [{:key, 1, :role, nil, ["role.role"]}]
    end

    test "spells nothing for a path inside a quantifier" do
      assert hints_of(
               &predicate_hints/2,
               "any(message <- messages, message.author.name == \"x\")",
               []
             ) == []
    end

    test "spells nothing at the top of a filter" do
      assert hints_of(&predicate_hints/2, "title == name and position in [1]", []) == []
    end

    test "spells a name a quantifier binds on each row, though a variable holds it too" do
      assert hints_of(
               &predicate_hints/2,
               "any(message <- messages, created_at > message.edited_at)",
               [:message]
             ) == [
               {:operand, 1, :edited_at, nil, ["message.edited_at", "edited_at"]},
               {:key, 1, {:outer, 1, :created_at}, nil, ["message.created_at", "created_at"]}
             ]
    end

    test "hints each side of and and or" do
      assert hints_of(&predicate_hints/2, "title == search or (body == search and a == 1)", [
               :search
             ]) == [{:operand, 0, :search, @fix, []}, {:operand, 0, :search, @fix, []}]
    end

    test "hints nothing for a name no variable holds" do
      assert hints_of(&predicate_hints/2, "title == name", []) == []
    end

    test "hints nothing for a membership" do
      assert hints_of(&predicate_hints/2, "search in [1, 2]", [:search]) == []
    end

    test "hints nothing for a negated membership" do
      assert hints_of(&predicate_hints/2, "search not in [1, 2]", [:search]) == []
    end

    test "hints nothing for a keyword list" do
      assert hints_of(&predicate_hints/2, "[title: ^search]", [:search]) == []
    end

    test "hints nothing for pinned predicates" do
      assert hints_of(&predicate_hints/2, "^search", [:search]) == []
    end
  end

  describe "predicates/2" do
    test "names a backfill word on the left side of a comparison" do
      assert_error Hologram.CompileError,
                   ~s[lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: coalesce(a, "x") - if you meant the query word coalesce, it works only in a migration's backfill: for now],
                   fn -> lower_predicates(~s[coalesce(a, "x") == "y"]) end
    end

    test "names a backfill word on the right side of a comparison" do
      assert_error Hologram.CompileError,
                   ~r/a comparison operand is .* got: split\(b, " "\) - .* - if you meant the query word split, it works only in a migration's backfill: for now$/,
                   fn -> lower_predicates(~s[a == split(b, " ")]) end
    end

    test "names a backfill word in a membership" do
      assert_error Hologram.CompileError, ~r/if you meant the query word split/, fn ->
        lower_predicates(~s[a in split(b, ",")])
      end
    end

    test "names a backfill word as a quantifier's source" do
      assert_error Hologram.CompileError, ~r/if you meant the query word split/, fn ->
        lower_predicates(~s[any(split(a, ","))])
      end
    end

    test "names a backfill word in a list of predicates" do
      assert_error Hologram.CompileError, ~r/if you meant the query word coalesce/, fn ->
        lower_predicates(~s{[coalesce(a, "x")]})
      end
    end

    test "names a backfill word making up the whole filter" do
      assert_error Hologram.CompileError,
                   ~r/unsupported expression in a filter: most_common\(a, b\) - .* - if you meant the query word most_common, it works only in a migration's backfill: for now$/,
                   fn -> lower_predicates("most_common(a, b)") end
    end

    test "raises on a call of new as the left side" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: the left side of a comparison names an attribute of the queried entity or a path to one, got: new(status)",
                   fn -> lower_predicates("new(status) == :approved") end
    end

    test "reads a call of new as the surrounding code's function, whose pin the refusal names" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a comparison operand is a literal, an attribute, a path or a pinned expression, got: new(term) - a value from the surrounding code is pinned: ^new(term)",
                   fn -> lower_predicates("status == new(term)") end
    end

    test "raises on a call of new as a quantifier's source" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a quantifier's source is a relationship or a path to one, got: new(project).members",
                   fn -> lower_predicates("any(new(project).members)") end
    end

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

    test "lowers a bound row's attribute compared with the same attribute of the row above" do
      assert lower_predicates("any(message <- messages, message.created_at > created_at)") == [
               any: {[:messages], [created_at: {:>, {:attribute, {:outer, 1, :created_at}}}]}
             ]
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

    test "lowers a comparison with a pinned attribute operand naming its left side" do
      assert lower_predicates("owner_id == ^{:attribute, :owner_id}") ==
               [owner_id: {:==, {:attribute, :owner_id}}]
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

    # A variable a macro generated is keyed by the counter its hygiene gave it, not by its context.
    test "lowers a pinned macro-generated variable" do
      variable = {:since, [counter: 7, line: 12], MyApp.Macros}
      {_value, _binding, env} = Code.eval_quoted_with_env({:=, [], [variable, nil]}, [], env())

      assert predicates(
               {:>, [line: 12], [{:created_at, [line: 12], nil}, {:^, [line: 12], [variable]}]},
               env
             ) ==
               [created_at: {:>, variable}]
    end

    # Elixir expands a name a macro marked if_undefined: :apply to a call of that name where no
    # variable holds it.
    test "lowers a pinned name that falls back to a call" do
      name = {:since, [if_undefined: :apply, line: 12], nil}

      assert predicates(
               {:>, [line: 12], [{:created_at, [line: 12], nil}, {:^, [line: 12], [name]}]},
               env()
             ) ==
               [created_at: {:>, name}]
    end

    test "lowers a pinned path over a bound row's name a variable also holds" do
      assert lower_predicates("any(message <- messages, message.created_at > ^message.edited_at)",
               message: %{edited_at: 5}
             ) == [any: {[:messages], [created_at: {:>, 5}]}]
    end

    # Code.eval_string/2 binds its binding's variables in the env a macro in the code expands in.
    test "lowers a pinned variable an evaluation binds" do
      code = "#{inspect(__MODULE__)}.lower_in_caller(created_at > ^since)"

      assert {[created_at: {:>, {:since, _meta, nil}}], _binding} =
               Code.eval_string("require #{inspect(__MODULE__)}; #{code}", since: nil)
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

    test "lowers a search" do
      assert lower_predicates("starts_with(username, ^query)", query: "jo") ==
               [username: {:starts_with, "jo"}]
    end

    test "lowers a search for a substring" do
      assert lower_predicates(~s|contains(body, "invoice")|) == [body: {:contains, "invoice"}]
    end

    test "lowers a search for another attribute" do
      assert lower_predicates("starts_with(email, username)") ==
               [email: {:starts_with, {:attribute, :username}}]
    end

    test "lowers a search inside a quantifier's condition" do
      assert lower_predicates("any(message <- messages, contains(message.body, ^query))",
               query: "hi"
             ) == [any: {[:messages], [body: {:contains, "hi"}]}]
    end

    test "lowers a search joined with a comparison" do
      assert lower_predicates(~s|starts_with(username, "jo") and active == true|) ==
               [username: {:starts_with, "jo"}, active: {:==, true}]
    end

    test "lowers a search on a path" do
      assert lower_predicates(~s|starts_with(author.username, "jo")|) ==
               [{[:author, :username], {:starts_with, "jo"}}]
    end

    test "lowers a search with a pinned term naming its attribute" do
      assert lower_predicates("starts_with(title, ^{:attribute, :title})") ==
               [title: {:starts_with, {:attribute, :title}}]
    end

    test "lowers a search with mode: :exact" do
      assert lower_predicates(~s|starts_with(code, "AB-", mode: :exact)|) ==
               [code: {:starts_with_exact, "AB-"}]

      assert lower_predicates(~s|contains(code, "-1", mode: :exact)|) ==
               [code: {:contains_exact, "-1"}]
    end

    test "lowers a search with mode: :loose" do
      assert lower_predicates(~s|starts_with(username, "jo", mode: :loose)|) ==
               [username: {:starts_with, "jo"}]
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

    test "raises on String.contains?/2" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: String.contains?/2 isn't available in a filter - write contains(body, ^query), which ignores case and accents, or contains(body, ^query, mode: :exact) to match byte for byte",
                   fn -> lower_predicates("String.contains?(body, ^query)", query: "hi") end
    end

    test "raises on String.starts_with?/2" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: String.starts_with?/2 isn't available in a filter - write starts_with(username, ^query), which ignores case and accents, or starts_with(username, ^query, mode: :exact) to match byte for byte",
                   fn ->
                     lower_predicates("String.starts_with?(username, ^query)", query: "jo")
                   end
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
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
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

    test "raises on a bound row's attribute compared with itself" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: message.created_at > message.created_at compares message.created_at with itself, which is always false",
                   fn ->
                     lower_predicates(
                       "any(message <- messages, message.created_at > message.created_at)"
                     )
                   end
    end

    test "raises on a bound row's attribute compared with itself, its name also a variable's, naming no pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: message.read_at > message.read_at compares message.read_at with itself, which is always false",
                   fn ->
                     lower(
                       &predicates(&1, env_binding(:message)),
                       "any(message <- messages, message.read_at > message.read_at)"
                     )
                   end
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
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: open_predicates() - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
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
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: not (a == 1 or b == 2) - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
                   fn -> lower_predicates("not (a == 1 or b == 2)") end
    end

    test "raises on a negated membership tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [status: {:not_in, [:done]}] - write it as an expression: status not in [:done]",
                   fn -> lower_predicates("[status: {:not_in, [:done]}]") end
    end

    test "raises on a negation that is not a membership" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: unsupported expression in a filter: not done - a filter is a comparison (==, !=, <, <=, >, >=, in, not in), a search (starts_with, contains), comparisons joined with and, alternatives joined with or, a quantifier over a relationship's rows (any, none, all), a keyword list of equalities, or a pinned list of predicates",
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

    test "raises on a path compared with itself" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: project.owner_id == project.owner_id compares project.owner_id with itself, which is always true",
                   fn -> lower_predicates("project.owner_id == project.owner_id") end
    end

    test "raises on a path compared with itself beside a variable of another name, naming no pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: project.owner_id == project.owner_id compares project.owner_id with itself, which is always true",
                   fn ->
                     lower(
                       &predicates(&1, env_binding(:owner_id)),
                       "project.owner_id == project.owner_id"
                     )
                   end
    end

    test "raises on a path compared with itself beside a variable of its first name, naming the pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: project.owner_id == project.owner_id compares project.owner_id with itself, which is always true - a value from the surrounding code is pinned: ^project.owner_id",
                   fn ->
                     lower(
                       &predicates(&1, env_binding(:project)),
                       "project.owner_id == project.owner_id"
                     )
                   end
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

    test "raises on a pinned bound row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^message pins message, the row a quantifier binds - its fields read without a pin: message.<attribute>",
                   fn -> lower_predicates("any(message <- messages, message.id == ^message)") end
    end

    test "raises on a pinned name no variable holds, naming the field" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^created_at pins created_at, which no variable holds here - inside a filter a name without a pin reads a field of the queried entity: created_at",
                   fn -> lower_predicates("updated_at > ^created_at") end
    end

    test "raises on a pinned name no variable holds as a search term" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^name pins name, which no variable holds here - inside a filter a name without a pin reads a field of the queried entity: name",
                   fn -> lower_predicates("contains(title, ^name)") end
    end

    test "raises on a pinned name no variable holds inside a nested quantifier, naming the nearest bound row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^archived_at pins archived_at, which no variable holds here - inside a filter a name without a pin reads a field of the queried entity: archived_at - or of the row message binds, through its name: message.archived_at",
                   fn ->
                     lower_predicates(
                       "any(channel <- channels, any(message <- channel.messages, message.created_at > ^archived_at))"
                     )
                   end
    end

    test "raises on a pinned name no variable holds inside a quantifier, naming the bound row too" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^last_read_at pins last_read_at, which no variable holds here - inside a filter a name without a pin reads a field of the queried entity: last_read_at - or of the row message binds, through its name: message.last_read_at",
                   fn ->
                     lower_predicates(
                       "any(message <- messages, message.created_at > ^last_read_at)"
                     )
                   end
    end

    test "raises on a pinned path no variable holds, naming the field" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^project.owner_id pins project, which no variable holds here - inside a filter a name without a pin reads a field of the queried entity: project.owner_id",
                   fn -> lower_predicates("assignee_id == ^project.owner_id") end
    end

    test "raises on a pinned path over a bound row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: ^message.edited_at pins message, the row a quantifier binds - its fields read without a pin: message.edited_at",
                   fn ->
                     lower_predicates(
                       "any(message <- messages, message.created_at > ^message.edited_at)"
                     )
                   end
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

    test "raises on a search as a list entry" do
      assert_error Hologram.CompileError,
                   ~s|lib/my_app/queries.ex:12: a keyword predicate is attribute: value, got: starts_with(username, "jo") - join comparisons with and|,
                   fn -> lower_predicates(~s|[starts_with(username, "jo"), active == true]|) end
    end

    test "raises on a search for the attribute it reads" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with(title, title) compares title with itself, which only says title isn't nil - write title != nil",
                   fn -> lower_predicates("starts_with(title, title)") end
    end

    test "raises on a search for the attribute it reads beside a variable of its name, naming the pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with(title, title) compares title with itself, which only says title isn't nil - a value from the surrounding code is pinned: ^title",
                   fn ->
                     lower(&predicates(&1, env_binding(:title)), "starts_with(title, title)")
                   end
    end

    test "raises on a search for the attribute it reads with mode: :exact" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: contains(title, title, mode: :exact) compares title with itself, which only says title isn't nil - write title != nil",
                   fn -> lower_predicates("contains(title, title, mode: :exact)") end
    end

    test "raises on a search operator tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   ~s|lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [username: {:starts_with, "jo"}] - write it as an expression: starts_with(username, "jo")|,
                   fn -> lower_predicates(~s|[username: {:starts_with, "jo"}]|) end
    end

    test "raises on a search with a mode other than :loose or :exact" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with takes one option, mode: :loose (the default) or mode: :exact, got: [mode: :strict]",
                   fn -> lower_predicates(~s|starts_with(code, "AB", mode: :strict)|) end
    end

    test "raises on a search with a pinned mode" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with takes its mode option written in place, got: mode: ^mode - the mode decides what the query reads, so write mode: :loose or mode: :exact",
                   fn ->
                     lower_predicates(~s|starts_with(code, "AB", mode: ^mode)|, mode: :exact)
                   end
    end

    test "raises on a search with a pinned option" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with takes its mode option written in place, got: ^opts - the mode decides what the query reads, so write mode: :loose or mode: :exact",
                   fn -> lower_predicates(~s|starts_with(code, "AB", ^opts)|, opts: []) end
    end

    test "raises on a search with an option other than mode" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: contains takes one option, mode: :loose (the default) or mode: :exact, got: [case: :exact]",
                   fn -> lower_predicates(~s|contains(code, "AB", case: :exact)|) end
    end

    test "raises on a search without a term" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: starts_with takes an attribute, a search term and, optionally, mode: :exact - starts_with(name, ^term) or starts_with(name, ^term, mode: :exact) - got: starts_with(code)",
                   fn -> lower_predicates("starts_with(code)") end
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

    # A variable a macro generated is keyed by the counter its hygiene gave it, not by its context.
    test "raises on an attribute compared with itself beside a macro-generated variable of its name, naming the pin" do
      variable = {:inserted_at, [counter: 7, line: 12], MyApp.Macros}
      {_value, _binding, env} = Code.eval_quoted_with_env({:=, [], [variable, nil]}, [], env())

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: inserted_at >= inserted_at compares inserted_at with itself, which only says inserted_at isn't nil - a value from the surrounding code is pinned: ^inserted_at",
                   fn -> predicates({:>=, [line: 12], [variable, variable]}, env) end
    end

    test "raises on an attribute compared with itself beside a variable of its name, naming the pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: inserted_at >= inserted_at compares inserted_at with itself, which only says inserted_at isn't nil - a value from the surrounding code is pinned: ^inserted_at",
                   fn ->
                     lower(
                       &predicates(&1, env_binding(:inserted_at)),
                       "inserted_at >= inserted_at"
                     )
                   end
    end

    test "raises on an attribute compared with itself by ==" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: owner_id == owner_id compares owner_id with itself, which is always true",
                   fn -> lower_predicates("owner_id == owner_id") end
    end

    test "raises on an attribute compared with itself by an operator that is always false" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: updated_at != updated_at compares updated_at with itself, which is always false",
                   fn -> lower_predicates("updated_at != updated_at") end

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: updated_at < updated_at compares updated_at with itself, which is always false",
                   fn -> lower_predicates("updated_at < updated_at") end

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: updated_at > updated_at compares updated_at with itself, which is always false",
                   fn -> lower_predicates("updated_at > updated_at") end
    end

    test "raises on an attribute compared with itself by an ordering operator taking equality" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: updated_at <= updated_at compares updated_at with itself, which only says updated_at isn't nil - write updated_at != nil",
                   fn -> lower_predicates("updated_at <= updated_at") end

      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: updated_at >= updated_at compares updated_at with itself, which only says updated_at isn't nil - write updated_at != nil",
                   fn -> lower_predicates("updated_at >= updated_at") end
    end

    test "raises on an attribute compared with itself in an alternative" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: owner_id != owner_id compares owner_id with itself, which is always false",
                   fn -> lower_predicates("archived == true or owner_id != owner_id") end
    end

    test "raises on an attribute of the queried row compared with itself inside a quantifier" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: created_at < created_at compares created_at with itself, which is always false",
                   fn -> lower_predicates("any(message <- messages, created_at < created_at)") end
    end

    test "raises on an exact search operator tuple as a keyword value" do
      assert_error Hologram.CompileError,
                   ~s|lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [code: {:contains_exact, "-1"}] - write it as an expression: contains(code, "-1", mode: :exact)|,
                   fn -> lower_predicates(~s|[code: {:contains_exact, "-1"}]|) end
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

    # A pinned call is the surrounding code's own function, whatever its name, so the data form
    # gets the hint for the expression it means.
    test "passes over a pinned user_id() call in a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:7: a keyword predicate is an equality, got: [owner_id: {:==, ^user_id()}] - write it as an expression: owner_id == ^user_id()",
                   fn -> lower_predicates("[owner_id: {:==, ^user_id()}]") end
    end

    test "raises on user_id() as a bound of a range" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("owner_id in 1..user_id()") end
    end

    test "raises on user_id() as a comparison operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("owner_id == user_id()") end
    end

    test "raises on user_id() as a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("[owner_id: user_id()]") end
    end

    test "raises on user_id() as a membership element" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("owner_id in [user_id()]") end
    end

    test "raises on user_id() as a membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("owner_id in user_id()") end
    end

    test "raises on user_id() as a search term" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("contains(name, user_id())") end
    end

    test "raises on user_id() as an element of a membership list in a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("[owner_id: [user_id()]]") end
    end

    test "raises on user_id() as an operator tuple's operand in a keyword value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("[owner_id: {:==, user_id()}]") end
    end

    test "raises on user_id() in a quantifier's condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn ->
                     lower_predicates("any(member <- members, member.user_id == user_id())")
                   end
    end

    test "raises on user_id() in an alternative" do
      assert_error Hologram.CompileError,
                   "lib/my_app/queries.ex:12: a filter can't name the acting user - only a policy condition can, got: user_id() - to filter by a user's id, pin a variable holding it: ^user_id",
                   fn -> lower_predicates("a == 1 or owner_id == user_id()") end
    end
  end
end
