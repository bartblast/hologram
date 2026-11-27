defmodule Hologram.Policy.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Expression

  # The code is parsed at line 12 of an allow line written at line 7, so a refusal located at a
  # node names line 12 and one located at a node carrying no line (a literal) names the line's.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/policies.ex"), line: 7}
  end

  # Parses the options of an allow line for the given operation, lowers them and evaluates what they
  # lowered to in this module, with the given binding standing for the caller's variables.
  defp lower_spec(code, binding \\ [], operation \\ :update) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> then(&spec(operation, &1, env_binding(Keyword.keys(binding))))
      |> Code.eval_quoted(binding, env())

    value
  end

  # The env of a line written where variables of the given names are bound, as a pinned name reads
  # one.
  defp env_binding(names) do
    assignments = Enum.map(names, &{:=, [], [{&1, [], nil}, nil]})

    {_value, _binding, env} =
      Code.eval_quoted_with_env({:__block__, [], [nil | assignments]}, [], env())

    env
  end

  describe "spec/3" do
    test "carries the hints of a condition naming a name inside a quantifier" do
      assert lower_spec("[when: any(member <- members, member.role == :admin)]") == [
               when: [any: {[:members], [role: {:==, :admin}]}],
               __name_hints__: [{:key, 1, :role, nil, ["member.role", "role"]}]
             ]
    end

    # The declaration refuses such a spec printing it whole, where hints would only show.
    test "carries no hints in a spec holding anything but options" do
      assert lower_spec("[:foo, when: any(member <- members, member.role == :admin)]") == [
               :foo,
               when: [any: {[:members], [role: {:==, :admin}]}]
             ]
    end

    test "carries no hints for a condition with nothing to hint" do
      assert lower_spec("[when: owner_id == user_id()]") == [when: [owner_id: {:==, {:actor}}]]
    end

    test "lowers new() on an update line to the row one level above" do
      assert lower_spec("[when: new(status) == :approved]") == [
               when: [{{:outer, 1, :status}, {:==, :approved}}]
             ]
    end

    test "lowers a path inside new()" do
      assert lower_spec("[when: new(project.archived) == false]") == [
               when: [{{:outer, 1, [:project, :archived]}, {:==, false}}]
             ]
    end

    test "lowers a path dotted after new() to the same name" do
      assert lower_spec("[when: new(project).archived == false]") == [
               when: [{{:outer, 1, [:project, :archived]}, {:==, false}}]
             ]
    end

    test "lowers new() as an operand" do
      assert lower_spec("[when: priority <= new(priority)]") == [
               when: [priority: {:<=, {:attribute, {:outer, 1, :priority}}}]
             ]
    end

    test "lowers new() in a membership and a search" do
      assert lower_spec(~s/[when: new(status) in [:a, :b] and contains(new(title), "x")]/) == [
               when: [
                 {{:outer, 1, :status}, {:in, [:a, :b]}},
                 {{:outer, 1, :title}, {:contains, "x"}}
               ]
             ]
    end

    test "lowers new() as a quantifier's source" do
      lowered = lower_spec("[when: any(member <- new(project).members, member.active == true)]")

      assert lowered[:when] == [
               any: {{:outer, 1, [:project, :members]}, [active: {:==, true}]}
             ]
    end

    test "lowers new() inside a quantifier's condition to the level past the rule's row" do
      lowered = lower_spec("[when: any(member <- members, member.level >= new(priority))]")

      assert lowered[:when] == [
               any: {[:members], [level: {:>=, {:attribute, {:outer, 2, :priority}}}]}
             ]
    end

    test "keeps an attribute named new" do
      assert lower_spec("[when: new == 1]") == [when: [new: {:==, 1}]]
    end

    test "carries the swapped hint for a variable compared with new()" do
      assert lower_spec("[when: search == new(title)]", search: "x") == [
               when: [search: {:==, {:attribute, {:outer, 1, :title}}}],
               __name_hints__: [
                 {:key, 0, :search,
                  "a value from the surrounding code is pinned, on the right side: new(title) == ^search",
                  []}
               ]
             ]
    end

    test "gives no swapped hint when new() reads the name the left side starts at" do
      assert lower_spec("[when: search == new(search)]", search: "x") == [
               when: [search: {:==, {:attribute, {:outer, 1, :search}}}]
             ]
    end

    test "raises on new() inside a larger operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(priority) + 1",
                   fn -> lower_spec("[when: priority <= new(priority) + 1]") end
    end

    test "raises on new() inside a range in a membership list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(low)..5",
                   fn -> lower_spec("[when: priority in [new(low)..5]]") end
    end

    test "raises on new() inside a larger membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(allowed) ++ [1]",
                   fn -> lower_spec("[when: priority in new(allowed) ++ [1]]") end
    end

    test "raises on new() inside a larger operand on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(priority) + 1",
                   fn -> lower_spec("[when: priority <= new(priority) + 1]", [], :read) end
    end

    test "keeps a pinned call of new as the surrounding code's own" do
      quoted = Code.string_to_quoted!("[when: priority == ^new(1)]", line: 12)

      assert [when: [priority: {:==, {:new, _meta, [1]}}]] = spec(:update, quoted, env())
    end

    test "raises on new() around a value as a source with an unbound condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() takes a field of the row being updated, or a path through its to-one relationships, got: new(1)",
                   fn -> lower_spec("[when: any(new(1), task.done == true)]") end
    end

    test "raises on a value holding new() as a source with an unbound condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(tags) ++ [1]",
                   fn -> lower_spec("[when: any(new(tags) ++ [1], tag.done == true)]") end
    end

    test "names the search with new() in a refusal of a String function" do
      assert_error Hologram.CompileError,
                   ~s/lib\/my_app\/policies.ex:12: String.contains?\/2 isn't available in a condition - write contains(new(title), "x"), which ignores case and accents, or contains(new(title), "x", mode: :exact) to match byte for byte/,
                   fn -> lower_spec(~s/[when: String.contains?(new(title), "x")]/) end
    end

    test "raises on new() in a String function on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(title)",
                   fn -> lower_spec(~s/[when: String.contains?(new(title), "x")]/, [], :read) end
    end

    test "raises on new() around a value in a String function" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() takes a field of the row being updated, or a path through its to-one relationships, got: new(1)",
                   fn -> lower_spec(~s/[when: String.contains?(new(1), "x")]/) end
    end

    test "raises on a larger value holding new() in a String function" do
      assert_error Hologram.CompileError,
                   ~s/lib\/my_app\/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(a) <> "x"/,
                   fn -> lower_spec(~s/[when: String.contains?(title, new(a) <> "x")]/) end
    end

    test "raises on new() as a membership element" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(other)",
                   fn -> lower_spec("[when: status in [new(other)]]") end
    end

    test "raises on new() as a membership operand" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(allowed)",
                   fn -> lower_spec("[when: status in new(allowed)]") end
    end

    test "raises on new() as a range bound" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() stands alone on one side of a comparison, not inside a list, a range or another expression, got: new(low)",
                   fn -> lower_spec("[when: priority in new(low)..5]") end
    end

    test "raises on new() in a membership on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(other)",
                   fn -> lower_spec("[when: status in [new(other)]]", [], :read) end
    end

    test "raises on new() as a source with an unbound condition on another operation's line" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(tasks)",
                   fn -> lower_spec("[when: any(new(tasks), task.done == true)]", [], :read) end
    end

    test "raises on new() compared with itself" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new(status) == new(status) compares new(status) with itself, which is always true",
                   fn -> lower_spec("[when: new(status) == new(status)]") end
    end

    test "raises on new() on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(status)",
                   fn -> lower_spec("[when: new(status) == :approved]", [], :read) end
    end

    test "raises on new() on a line whose operation isn't written as an atom" do
      operation = quote(do: @operation)

      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(status)",
                   fn -> lower_spec("[when: new(status) == :approved]", [], operation) end
    end

    test "raises on new() around a row a quantifier binds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() reads the row being updated, and member is a row a quantifier binds, got: new(member.level)",
                   fn ->
                     lower_spec("[when: any(member <- members, new(member.level) == 1)]")
                   end
    end

    test "raises on new() around a value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() takes a field of the row being updated, or a path through its to-one relationships, got: new(1)",
                   fn -> lower_spec("[when: new(1) == 2]") end
    end

    test "raises on new() with no argument" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() takes a field of the row being updated, or a path through its to-one relationships, got: new()",
                   fn -> lower_spec("[when: new() == 2]") end
    end

    test "lowers has_role on the new row" do
      assert lower_spec("[when: has_role(:member, new(trip.project))]") == [
               when: [{{:has_role, :member}, [:trip, :project]}]
             ]
    end

    test "lowers can on the new row" do
      assert lower_spec("[when: can(:update, new(project))]") == [
               when: [{{:can, :update}, [:project]}]
             ]
    end

    test "lowers has_role and can in the alternatives of a disjunction" do
      assert lower_spec("[when: has_role(:member, new(a)) or can(:update, new(b))]") == [
               when: [or: [[{{:has_role, :member}, [:a]}], [{{:can, :update}, [:b]}]]]
             ]
    end

    test "lowers a pinned role" do
      assert lower_spec("[when: has_role(^role, new(project))]", role: :member) == [
               when: [{{:has_role, :member}, [:project]}]
             ]
    end

    test "raises on has_role of the stored row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role reads the row a change leads to, got: has_role(:member, project) - write has_role(:member, new(project)), and the stored row goes in to: {:member, project}, which applies to the whole line and holds on any one of its roles, so an or needs one allow line per alternative",
                   fn -> lower_spec("[when: has_role(:member, project)]") end
    end

    test "raises on can of the stored row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can reads the row a change leads to, got: can(:update, project) - write can(:update, new(project)), and the stored row goes in via: {:update, project}, which applies to the whole line, so an or needs one allow line per alternative",
                   fn -> lower_spec("[when: can(:update, project)]") end
    end

    test "raises on has_role inside a quantifier" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role stands at the top of a condition or in an or, not inside a quantifier, got: has_role(:member, new(project))",
                   fn ->
                     lower_spec("[when: any(tag <- tags, has_role(:member, new(project)))]")
                   end
    end

    test "raises on has_role on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role works only in the when: condition of an allow :update line, with the operation written as that atom, got: has_role(:member, new(project))",
                   fn -> lower_spec("[when: has_role(:member, new(project))]", [], :read) end
    end

    test "raises on has_role? in a condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition - write has_role(:member, new(project)), got: has_role?(:member, new(project))",
                   fn -> lower_spec("[when: has_role?(:member, new(project))]") end
    end

    test "keeps the operation and the target in the name it suggests for can?" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write can(:read, new(project)), got: can?(:read, new(project))",
                   fn -> lower_spec("[when: can?(:read, new(project))]") end
    end

    test "keeps the role and the target in the name it suggests for has_role?" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition - write has_role(:admin, new(project.owner)), got: has_role?(:admin, new(project.owner))",
                   fn -> lower_spec("[when: has_role?(:admin, new(project.owner))]") end
    end

    test "says a condition asks about the acting user when can? names a user" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user, so write can(:read, new(project)), got: can?(user, :read, new(project))",
                   fn -> lower_spec("[when: can?(user, :read, new(project))]") end
    end

    test "says a condition asks about the acting user when has_role? names a user" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition - a condition asks only about the acting user, so write it like has_role(:member, new(project)), got: has_role?(user, :admin)",
                   fn -> lower_spec("[when: has_role?(user, :admin)]") end
    end

    test "says a condition asks about the acting user when can? names a user and values" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user and passes no values, so write can(:update, new(project)), got: can?(user, :update, new(project), status: :done)",
                   fn ->
                     lower_spec("[when: can?(user, :update, new(project), status: :done)]")
                   end
    end

    test "names no user when can? starts with the operation and has values" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition passes no values, so write can(:update, new(project)), and the stored row goes in via: {:update, project}, which applies to the whole line, so an or needs one allow line per alternative, got: can?(:update, project, status: :done)",
                   fn -> lower_spec("[when: can?(:update, project, status: :done)]") end
    end

    test "says a condition asks about the acting user when can? names a pinned user" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user, so write can(:read, new(project)), got: can?(^other_user, :read, new(project))",
                   fn -> lower_spec("[when: can?(^other_user, :read, new(project))]") end
    end

    test "says a condition asks about the acting user when can? names a user and a pinned operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user, so write it like can(:update, new(project)), got: can?(user, ^operation, new(project))",
                   fn -> lower_spec("[when: can?(user, ^operation, new(project))]") end
    end

    test "names no user when can? starts with a variable operation and has values" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition passes no values, so write it like can(:update, new(project)), got: can?(operation, new(project), status: :done)",
                   fn -> lower_spec("[when: can?(operation, new(project), status: :done)]") end
    end

    test "names only the user when can? names one and a variable operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user, so write it like can(:update, new(project)), got: can?(user, operation, new(project))",
                   fn -> lower_spec("[when: can?(user, operation, new(project))]") end
    end

    test "names the user and the values when can? has both and a variable operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user and passes no values, so write it like can(:update, new(project)), got: can?(user, operation, new(project), status: :done)",
                   fn ->
                     lower_spec("[when: can?(user, operation, new(project), status: :done)]")
                   end
    end

    test "names the values when can? pins its row and names no user" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition passes no values, so write it like can(:update, new(project)), got: can?(operation, ^project, status: :done)",
                   fn -> lower_spec("[when: can?(operation, ^project, status: :done)]") end
    end

    test "says a condition asks about the acting user when has_role? names a user and a role module" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition - a condition asks only about the acting user, so write it like has_role(:member, new(project)), got: has_role?(user, Admin)",
                   fn -> lower_spec("[when: has_role?(user, Admin)]") end
    end

    test "gives an example for a pinned operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write it like can(:update, new(project)), got: can?(^operation, new(project))",
                   fn -> lower_spec("[when: can?(^operation, new(project))]") end
    end

    test "gives an example for an atom spelled as a module" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write it like can(:update, new(project)), got: can?(Foo, new(project))",
                   fn -> lower_spec(~s/[when: can?(:"Elixir.Foo", new(project))]/) end
    end

    test "keeps the operation and the stored row in what it suggests for can?" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write can(:read, new(project)), and the stored row goes in via: {:read, project}, which applies to the whole line, so an or needs one allow line per alternative, got: can?(:read, project)",
                   fn -> lower_spec("[when: can?(:read, project)]") end
    end

    test "leaves out the user when can? is asked of the stored row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - a condition asks only about the acting user, so write can(:read, new(judge)), and the stored row goes in via: {:read, judge}, which applies to the whole line, so an or needs one allow line per alternative, got: can?(user, :read, judge)",
                   fn -> lower_spec("[when: can?(user, :read, judge)]") end
    end

    test "keeps the role and the stored row in what it suggests for has_role?" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition - a condition asks only about the acting user, so write has_role(:admin, new(project.owner)), and the stored row goes in to: {:admin, project.owner}, which applies to the whole line and holds on any one of its roles, so an or needs one allow line per alternative, got: has_role?(user, :admin, project.owner)",
                   fn -> lower_spec("[when: has_role?(user, :admin, project.owner)]") end
    end

    test "gives an example when the target is no row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write it like can(:update, new(project)), got: can?(:read, 1)",
                   fn -> lower_spec("[when: can?(:read, 1)]") end
    end

    test "raises on can? in a condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: can? isn't available in a condition - write can(:update, new(project)), got: can?(:update, new(project))",
                   fn -> lower_spec("[when: can?(:update, new(project))]") end
    end

    test "raises on has_role with the wrong number of arguments" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role takes a role and new() of a relationship - has_role(:member, new(project)) - got: has_role(:member)",
                   fn -> lower_spec("[when: has_role(:member)]") end
    end

    test "raises on has_role naming its role with a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role names a role with an atom or a pinned expression, got: member in has_role(member, new(project))",
                   fn -> lower_spec("[when: has_role(member, new(project))]") end
    end

    test "raises on new() in a to: reference" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {:member, new(project)} - a role on the row a change leads to goes in when: has_role(:member, new(project))",
                   fn -> lower_spec("[to: {:member, new(project)}]") end
    end

    test "raises on new() in a to: reference listed with other roles" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {:member, new(project)} - a role on the row a change leads to goes in when: has_role(:member, new(project)) on a copy of this line with no to:, while this line keeps the other roles in to:, since to: holds on any one of its roles",
                   fn -> lower_spec("[to: [:admin, {:member, new(project)}]]") end
    end

    test "raises on new() in a one-reference to: list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {:member, new(project)} - a role on the row a change leads to goes in when: has_role(:member, new(project))",
                   fn -> lower_spec("[to: [{:member, new(project)}]]") end
    end

    test "raises on new() as a via: relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via reads the stored row, got: new(project) - the row a change leads to goes in when: can(:update, new(project))",
                   fn -> lower_spec("[via: new(project)]") end
    end

    test "raises on new() in a via: tuple" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via reads the stored row, got: {:archive, new(project)} - the row a change leads to goes in when: can(:archive, new(project))",
                   fn -> lower_spec("[via: {:archive, new(project)}]") end
    end

    test "raises on new() written first in a via: tuple" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via reads the stored row, got: {new(project), :archive} - the row a change leads to goes in when: can(:archive, new(project))",
                   fn -> lower_spec("[via: {new(project), :archive}]") end
    end

    test "raises on new() in via: on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(project)",
                   fn -> lower_spec("[via: new(project)]", [], :read) end
    end

    test "raises on new() in to: on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: new() works only in the when: condition of an allow :update line, with the operation written as that atom, got: new(project)",
                   fn -> lower_spec("[to: {:member, new(project)}]", [], :read) end
    end

    test "raises on new() as a whole to: reference" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: new(project) - a role on the row a change leads to goes in when: has_role(:role, new(project))",
                   fn -> lower_spec("[to: new(project)]") end
    end

    test "gives a malformed new() in to: the option's own refusal" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:member, new(1)}",
                   fn -> lower_spec("[to: {:member, new(1)}]") end
    end

    test "raises on has_role with a target that is no relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role takes a role and new() of a relationship - has_role(:member, new(project)) - got: has_role(:member, :project)",
                   fn -> lower_spec("[when: has_role(:member, :project)]") end
    end

    test "raises on a pinned role no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^member pins member, which no variable holds here - has_role names a role with an atom: :member",
                   fn -> lower_spec("[when: has_role(^member, new(project))]") end
    end

    test "refuses a pin no variable holds before naming the stored row" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^member pins member, which no variable holds here - has_role names a role with an atom: :member",
                   fn -> lower_spec("[when: has_role(^member, project)]") end
    end

    test "names has_role with a pinned role a variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {^role, new(project)} - a role on the row a change leads to goes in when: has_role(^role, new(project))",
                   fn -> lower_spec("[to: {^role, new(project)}]", role: :member) end
    end

    test "names has_role with an example for a pinned role no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {^role, new(project)} - a role on the row a change leads to goes in when: has_role(:role, new(project))",
                   fn -> lower_spec("[to: {^role, new(project)}]") end
    end

    test "refuses a pinned path no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^member.role pins member, which no variable holds here - has_role names a role with an atom or a pinned expression",
                   fn -> lower_spec("[when: has_role(^member.role, project)]") end
    end

    test "names has_role with an example for a pinned path no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {^member.role, new(project)} - a role on the row a change leads to goes in when: has_role(:role, new(project))",
                   fn -> lower_spec("[to: {^member.role, new(project)}]") end
    end

    test "names has_role with a pinned path a variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to reads the stored row, got: {^member.role, new(project)} - a role on the row a change leads to goes in when: has_role(^member.role, new(project))",
                   fn ->
                     lower_spec("[to: {^member.role, new(project)}]", member: %{role: :lead})
                   end
    end

    test "names can with an example for a pinned operation no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via reads the stored row, got: {^operation, new(project)} - the row a change leads to goes in when: can(:update, new(project))",
                   fn -> lower_spec("[via: {^operation, new(project)}]") end
    end

    test "names no replacement for has_role? on a line for another operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition, got: has_role?(:member, new(project))",
                   fn -> lower_spec("[when: has_role?(:member, new(project))]", [], :read) end
    end

    test "names no replacement for has_role? inside a quantifier" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: has_role? isn't available in a condition, got: has_role?(:member, new(project))",
                   fn ->
                     lower_spec("[when: any(tag <- tags, has_role?(:member, new(project)))]")
                   end
    end

    test "keeps __MODULE__ as a role module" do
      assert lower_spec("[to: __MODULE__]") == [to: __MODULE__]
    end

    test "keeps __MODULE__ as the type of a type reference" do
      assert lower_spec("[to: {:moderator, __MODULE__}]") == [to: {:moderator, __MODULE__}]
    end

    test "lowers the bare field names of an only option to atoms" do
      assert lower_spec("[only: [status, assignee]]") == [only: [:status, :assignee]]
    end

    test "lowers the bare field names of an except option to atoms" do
      assert lower_spec("[except: [status, assignee]]") == [except: [:status, :assignee]]
    end

    test "lowers a pinned field list to its value" do
      assert lower_spec("[only: ^fields]", fields: [:topic]) == [only: [:topic]]
    end

    test "lowers a pinned field name to its value" do
      assert lower_spec("[except: [title, ^field]]", field: :topic) == [except: [:title, :topic]]
    end

    test "keeps a nil field option for the declaration to refuse" do
      assert lower_spec("[only: nil]") == [only: nil]
    end

    test "raises on a field of an only option written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: only names a field with a bare name, got: :status - write status",
                   fn -> lower_spec("[only: [title, :status]]") end
    end

    test "raises on a field of an except option written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: except names a field with a bare name, got: :status - write status",
                   fn -> lower_spec("[except: [:status]]") end
    end

    test "raises on a pinned field name no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^status pins status, which no variable holds here - only names a field with a bare name, without the pin: status",
                   fn -> lower_spec("[only: [^status]]") end
    end

    test "raises on a pinned field list no variable holds" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^status pins status, which no variable holds here - only names fields with bare names in a list, like only: [status]",
                   fn -> lower_spec("[only: ^status]") end
    end

    test "raises on a lone field written as a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: only takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: status - write [status]",
                   fn -> lower_spec("[only: status]") end
    end

    test "raises on a lone field written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: except takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: :status - write [status]",
                   fn -> lower_spec("[except: :status]") end
    end

    test "gives no bracket hint for a lone atom no bare name spells" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: only takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: :Status",
                   fn -> lower_spec("[only: :Status]") end
    end

    test "raises on a field list read from a variable without a pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: only takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: fields - write ^fields",
                   fn -> lower_spec("[only: fields]", fields: [:topic]) end
    end

    test "raises on a field option that is no list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: only takes a list of fields written in place, or a pinned expression when the list comes from the surrounding code, got: true",
                   fn -> lower_spec("[only: true]") end
    end

    test "raises on a field written as a string" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: only names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: "topic"),
                   fn -> lower_spec(~s([only: ["topic"]])) end
    end

    test "raises on __MODULE__ as a field" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: only names a field with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_spec("[only: [__MODULE__]]") end
    end

    test "lowers the bare field names of a line taken from a policy module" do
      defmodule BareFieldsPolicyFixture do
        use Hologram.Policy

        allow :update, only: [topic]
      end

      defmodule BareFieldsEntityFixture do
        use Hologram.Entity

        attribute :topic, :string

        policy BareFieldsPolicyFixture
      end

      assert BareFieldsEntityFixture.__policies__() == [
               {:update, nil, nil, [], nil, {:only, [:topic]}}
             ]
    end

    test "raises on a repeated except option" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: allow :update takes the except option once - list the fields in one except option",
                   fn -> lower_spec("[except: [a], except: [b]]") end
    end

    test "keeps a name" do
      assert lower_spec("[as: :archive]") == [as: :archive]
    end

    test "lowers a pinned name to its value" do
      assert lower_spec("[as: ^name]", name: :archive) == [as: :archive]
    end

    test "keeps a name that is not an atom for the declaration to refuse" do
      assert lower_spec(~s([as: "archive"])) == [as: "archive"]
    end

    test "raises on a name written as a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: as names a rule with an atom, got: archive - write :archive",
                   fn -> lower_spec("[as: archive]") end
    end

    test "raises on a repeated name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: allow :update takes the as option once",
                   fn -> lower_spec("[as: :archive, as: :close]") end
    end

    test "keeps a nil option for the declaration to refuse" do
      assert lower_spec("[to: nil, via: nil]") == [to: nil, via: nil]
    end

    test "keeps a non-keyword element for the declaration to refuse" do
      assert lower_spec("[1, 2]") == [1, 2]
    end

    test "keeps a role module" do
      assert lower_spec("[to: MyApp.Roles.Admin]") == [to: MyApp.Roles.Admin]
    end

    test "keeps a role name" do
      assert lower_spec("[to: :editor]") == [to: :editor]
    end

    test "keeps a type reference" do
      assert lower_spec("[to: {:moderator, MyApp.Post}]") == [to: {:moderator, MyApp.Post}]
    end

    test "keeps an empty reference list for the declaration to refuse" do
      assert lower_spec("[to: []]") == [to: []]
    end

    test "lowers a bare line" do
      assert lower_spec("[]") == []
    end

    test "lowers a condition" do
      assert lower_spec("[when: priority < 3]") == [when: [priority: {:<, 3}]]
    end

    test "lowers a delegation" do
      assert lower_spec("[via: project]") == [via: :project]
    end

    test "lowers a delegation naming its operation" do
      assert lower_spec("[via: {:update, project}]") == [via: {:update, :project}]
    end

    test "lowers a delegation naming its operation through a path" do
      assert lower_spec("[via: {:update, stop.trip}]") == [via: {:update, [:stop, :trip]}]
    end

    test "lowers a delegation through a path" do
      assert lower_spec("[via: trip.user.profile]") == [via: [:trip, :user, :profile]]
    end

    test "lowers a list of references" do
      assert lower_spec("[to: [:editor, {:owner, project}, MyApp.Roles.Admin]]") ==
               [to: [:editor, {:owner, :project}, MyApp.Roles.Admin]]
    end

    test "lowers a pinned delegation" do
      assert lower_spec("[via: ^relationship]", relationship: :project) == [via: :project]
    end

    test "lowers a pinned delegation naming its operation" do
      assert lower_spec("[via: ^delegation]", delegation: {:update, :project}) ==
               [via: {:update, :project}]
    end

    test "lowers a pinned element of a reference list" do
      assert lower_spec("[to: [:owner, ^reference]]", reference: {:editor, :project}) ==
               [to: [:owner, {:editor, :project}]]
    end

    test "lowers a pinned operation in a delegation" do
      assert lower_spec("[via: {^operation, project}]", operation: :update) ==
               [via: {:update, :project}]
    end

    test "lowers a pinned reference list" do
      assert lower_spec("[to: ^roles]", roles: [:editor, :owner]) == [to: [:editor, :owner]]
    end

    test "lowers a pinned relationship in a delegation naming its operation" do
      assert lower_spec("[via: {:update, ^relationship}]", relationship: :project) ==
               [via: {:update, :project}]
    end

    test "lowers a pinned relationship in a reference" do
      assert lower_spec("[to: {:editor, ^relationship}]", relationship: :project) ==
               [to: {:editor, :project}]
    end

    test "lowers a pinned role in a reference" do
      assert lower_spec("[to: {^role, project}]", role: :editor) == [to: {:editor, :project}]
    end

    test "lowers a reference through a path" do
      assert lower_spec("[to: {:owner, trip.user}]") == [to: {:owner, [:trip, :user]}]
    end

    test "lowers a reference through a path in a list" do
      assert lower_spec("[to: [:editor, {:owner, trip.user}]]") ==
               [to: [:editor, {:owner, [:trip, :user]}]]
    end

    test "lowers a relationship reference" do
      assert lower_spec("[to: {:editor, project}]") == [to: {:editor, :project}]
    end

    test "lowers every option of one line" do
      assert lower_spec("[to: :editor, via: project, when: archived == false]") ==
               [to: :editor, via: :project, when: [archived: {:==, false}]]
    end

    test "raises on a delegation module attribute without a pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: @relationship - a value from the surrounding code is pinned: ^@relationship",
                   fn -> lower_spec("[via: @relationship]") end
    end

    test "raises on a delegation naming an operation tuple" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via takes a relationship, a path or an {operation, relationship} tuple, got: {{:grant_role, :editor}, trip}",
                   fn -> lower_spec("[via: {{:grant_role, :editor}, trip}]") end
    end

    test "raises on a delegation naming its operation with an atom relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via names a relationship with a bare name, got: :project - write project",
                   fn -> lower_spec("[via: {:update, :project}]") end
    end

    test "raises on a delegation naming its operation with a relationship to __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_spec("[via: {:update, __MODULE__}]") end
    end

    test "raises on a delegation operation written as a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names an operation with an atom, got: update - write :update",
                   fn -> lower_spec("[via: {update, project}]") end
    end

    test "raises on a delegation operation written as a bare name with a pinned relationship" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via puts the operation first, as an atom or pinned, and the relationship second, got: {update, ^relationship} - write {operation, relationship}, like {:update, trip}",
                   fn -> lower_spec("[via: {update, ^relationship}]") end
    end

    test "raises on a delegation path over __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__.parent() - a value from the surrounding code is pinned: ^__MODULE__.parent()",
                   fn -> lower_spec("[via: __MODULE__.parent]") end
    end

    test "raises on a delegation to __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_spec("[via: __MODULE__]") end
    end

    test "raises on a delegation with a path before a pinned operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the operation comes first in a delegation, got: {stop.trip, ^operation} - write {^operation, stop.trip}",
                   fn -> lower_spec("[via: {stop.trip, ^operation}]") end
    end

    test "raises on a delegation with a path first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the operation comes first in a delegation, got: {stop.trip, :update} - write {:update, stop.trip}",
                   fn -> lower_spec("[via: {stop.trip, :update}]") end
    end

    test "raises on a delegation with the relationship before a pinned operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via puts the operation first, as an atom or pinned, and the relationship second, got: {trip, ^operation} - write {operation, relationship}, like {:update, trip}",
                   fn -> lower_spec("[via: {trip, ^operation}]") end
    end

    test "raises on a delegation with the relationship first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the operation comes first in a delegation, got: {trip, :update} - write {:update, trip}",
                   fn -> lower_spec("[via: {trip, :update}]") end
    end

    test "raises on a pinned delegation no variable holds, naming the bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: ^project pins project, which no variable holds here - via names a relationship with a bare name, without the pin: project",
                   fn -> lower_spec("[via: ^project]") end
    end

    test "raises on a delegation written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via names a relationship with a bare name, got: :project - write project",
                   fn -> lower_spec("[via: :project]") end
    end

    test "raises on a malformed delegation" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: via names a relationship with a bare name or a path, or with a pinned expression when the name comes from the surrounding code, got: "project"),
                   fn -> lower_spec(~s([via: "project"])) end
    end

    test "raises on a malformed delegation operation" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: via takes a relationship, a path or an {operation, relationship} tuple, got: {"update", project}),
                   fn -> lower_spec(~s([via: {"update", project}])) end
    end

    test "raises on a malformed reference" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: "owner"),
                   fn -> lower_spec(~s([to: "owner"])) end
    end

    test "raises on a malformed reference in a list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:a, :b, :c}",
                   fn -> lower_spec("[to: [:editor, {:a, :b, :c}]]") end
    end

    test "raises on a nested delegation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via takes a relationship, a path or an {operation, relationship} tuple, got: {:update, {:read, trip}}",
                   fn -> lower_spec("[via: {:update, {:read, trip}}]") end
    end

    test "raises on a reference module attribute without a pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: @roles",
                   fn -> lower_spec("[to: @roles]") end
    end

    test "raises on a reference path over __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:editor, __MODULE__.parent()}",
                   fn -> lower_spec("[to: {:editor, __MODULE__.parent}]") end
    end

    test "raises on a reference with __MODULE__ first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {__MODULE__, :editor} - write {:editor, __MODULE__}",
                   fn -> lower_spec("[to: {__MODULE__, :editor}]") end
    end

    test "raises on a reference with a nil role" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: {nil, project}",
                   fn -> lower_spec("[to: {nil, project}]") end
    end

    test "raises on a reference with a nil scope" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship}, {role, path} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:editor, nil}",
                   fn -> lower_spec("[to: {:editor, nil}]") end
    end

    test "raises on a reference with a path before a pinned role" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {trip.user, ^role} - write {^role, trip.user}",
                   fn -> lower_spec("[to: {trip.user, ^role}]") end
    end

    test "raises on a reference with a path first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {trip.user, :owner} - write {:owner, trip.user}",
                   fn -> lower_spec("[to: {trip.user, :owner}]") end
    end

    test "raises on a reference with the scope first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {project, :editor} - write {:editor, project}",
                   fn -> lower_spec("[to: {project, :editor}]") end
    end

    test "raises on a relationship written as an atom in a reference" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to names a relationship with a bare name and puts the role first, got: {:editor, :project} - write {role, relationship}, like {:editor, project}",
                   fn -> lower_spec("[to: {:editor, :project}]") end
    end

    test "raises on a repeated condition" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: allow :update takes the when option once - join the conditions with and",
                   fn -> lower_spec("[when: a == 1, when: b == 2]") end
    end

    test "raises on a repeated delegation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: allow :update takes the via option once",
                   fn -> lower_spec("[via: project, via: folder]") end
    end

    test "raises on a repeated grant reference option" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: allow :update takes the to option once - list the role references in one to option",
                   fn -> lower_spec("[to: :editor, to: :owner]") end
    end

    test "raises on a role written as a bare name" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to names a role with an atom, got: editor - write :editor",
                   fn -> lower_spec("[to: editor]") end
    end

    test "raises on a type reference with the type first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {MyApp.Post, :moderator} - write {:moderator, MyApp.Post}",
                   fn -> lower_spec("[to: {MyApp.Post, :moderator}]") end
    end

    test "raises on an unknown option" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: unknown option :archived for allow :update - the allow options are as, except, only, to, via and when, and a condition goes in when: archived == false",
                   fn -> lower_spec("[archived: false]") end
    end

    test "raises on an unknown option for a grant lifecycle operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: unknown option :archived for allow {:grant_role, :viewer} - the allow options are as, except, only, to, via and when, and a condition goes in when: archived == false",
                   fn -> lower_spec("[archived: false]", [], {:grant_role, :viewer}) end
    end

    test "raises on an unknown option with a pinned value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: unknown option :priority for allow :update - the allow options are as, except, only, to, via and when, and a condition goes in when: priority == ^max",
                   fn -> lower_spec("[priority: ^max]") end
    end

    test "raises on an unknown option with user_id()" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: unknown option :owner_id for allow :update - the allow options are as, except, only, to, via and when, and a condition goes in when: owner_id == user_id()",
                   fn -> lower_spec("[owner_id: user_id()]") end
    end

    test "raises on an unknown option without an equality to suggest" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: unknown option :priority for allow :update - the allow options are as, except, only, to, via and when",
                   fn -> lower_spec("[priority: {:>=, 3}]") end
    end

    test "raises on options not written in place" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: allow :update takes a keyword list of options written in place, got: @opts",
                   fn -> lower_spec("@opts") end
    end

    test "raises the condition lowering's error" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: a condition is an expression, got: [shared: true] - write it as an expression: shared == true",
                   fn -> lower_spec("[when: [shared: true]]") end
    end
  end
end
