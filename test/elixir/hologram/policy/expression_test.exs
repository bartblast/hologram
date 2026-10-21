defmodule Hologram.Policy.ExpressionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Expression

  # The code is parsed at line 12 of an allow line written at line 7, so a refusal located at a
  # node names line 12 and one located at a node carrying no line (a literal) names the line's.
  defp env do
    %{__ENV__ | file: Path.join(File.cwd!(), "lib/my_app/policies.ex"), line: 7}
  end

  # Parses the options of an allow line for the given operation, lowers them and evaluates what they
  # lowered to in this module, with the given binding standing for the caller's values.
  defp lower_spec(code, binding \\ [], operation \\ :update) do
    {value, _binding} =
      code
      |> Code.string_to_quoted!(line: 12)
      |> then(&spec(operation, &1, env()))
      |> Code.eval_quoted(binding, env())

    value
  end

  describe "spec/3" do
    test "keeps __MODULE__ as a role module" do
      assert lower_spec("[to: __MODULE__]") == [to: __MODULE__]
    end

    test "keeps __MODULE__ as the type of a type reference" do
      assert lower_spec("[to: {:moderator, __MODULE__}]") == [to: {:moderator, __MODULE__}]
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

    test "lowers a list of references" do
      assert lower_spec("[to: [:editor, {:owner, project}, MyApp.Roles.Admin]]") ==
               [to: [:editor, {:owner, :project}, MyApp.Roles.Admin]]
    end

    test "lowers a pinned delegation" do
      assert lower_spec("[via: ^relationship]", relationship: :project) == [via: :project]
    end

    test "lowers a pinned element of a reference list" do
      assert lower_spec("[to: [:owner, ^reference]]", reference: {:editor, :project}) ==
               [to: [:owner, {:editor, :project}]]
    end

    test "lowers a pinned reference list" do
      assert lower_spec("[to: ^roles]", roles: [:editor, :owner]) == [to: [:editor, :owner]]
    end

    test "lowers a pinned relationship in a reference" do
      assert lower_spec("[to: {:editor, ^relationship}]", relationship: :project) ==
               [to: {:editor, :project}]
    end

    test "lowers a pinned role in a reference" do
      assert lower_spec("[to: {^role, project}]", role: :editor) == [to: {:editor, :project}]
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
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name, or with a pinned expression when the name comes from the surrounding code, got: @relationship - a value from the surrounding code is pinned: ^@relationship",
                   fn -> lower_spec("[via: @relationship]") end
    end

    test "raises on a delegation path" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via takes one relationship, got: trip.user",
                   fn -> lower_spec("[via: trip.user]") end
    end

    test "raises on a delegation to __MODULE__" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: via names a relationship with a bare name, or with a pinned expression when the name comes from the surrounding code, got: __MODULE__",
                   fn -> lower_spec("[via: __MODULE__]") end
    end

    test "raises on a delegation written as an atom" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: via names a relationship with a bare name, got: :project - write project",
                   fn -> lower_spec("[via: :project]") end
    end

    test "raises on a malformed delegation" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: via names a relationship with a bare name, or with a pinned expression when the name comes from the surrounding code, got: "project"),
                   fn -> lower_spec(~s([via: "project"])) end
    end

    test "raises on a malformed reference" do
      assert_error Hologram.CompileError,
                   ~s(lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: "owner"),
                   fn -> lower_spec(~s([to: "owner"])) end
    end

    test "raises on a malformed reference in a list" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:a, :b, :c}",
                   fn -> lower_spec("[to: [:editor, {:a, :b, :c}]]") end
    end

    test "raises on a reference module attribute without a pin" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: @roles",
                   fn -> lower_spec("[to: @roles]") end
    end

    test "raises on a reference with __MODULE__ first" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: the role comes first in a grant reference, got: {__MODULE__, :editor} - write {:editor, __MODULE__}",
                   fn -> lower_spec("[to: {__MODULE__, :editor}]") end
    end

    test "raises on a reference with a nil role" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: {nil, project}",
                   fn -> lower_spec("[to: {nil, project}]") end
    end

    test "raises on a reference with a nil scope" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: to takes a role name, a role module, a {role, relationship} or {role, entity type} tuple, a list of them, or a pinned expression, got: {:editor, nil}",
                   fn -> lower_spec("[to: {:editor, nil}]") end
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
                   "lib/my_app/policies.ex:7: unknown option :archived for allow :update - the allow options are to, via and when, and a condition goes in when: archived == false",
                   fn -> lower_spec("[archived: false]") end
    end

    test "raises on an unknown option for a grant lifecycle operation" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: unknown option :archived for allow {:grant_role, :viewer} - the allow options are to, via and when, and a condition goes in when: archived == false",
                   fn -> lower_spec("[archived: false]", [], {:grant_role, :viewer}) end
    end

    test "raises on an unknown option with a pinned value" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: unknown option :priority for allow :update - the allow options are to, via and when, and a condition goes in when: priority == ^max",
                   fn -> lower_spec("[priority: ^max]") end
    end

    test "raises on an unknown option with user_id()" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:12: unknown option :owner_id for allow :update - the allow options are to, via and when, and a condition goes in when: owner_id == user_id()",
                   fn -> lower_spec("[owner_id: user_id()]") end
    end

    test "raises on an unknown option without an equality to suggest" do
      assert_error Hologram.CompileError,
                   "lib/my_app/policies.ex:7: unknown option :priority for allow :update - the allow options are to, via and when",
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
