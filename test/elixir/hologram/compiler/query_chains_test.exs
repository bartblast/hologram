defmodule Hologram.Compiler.QueryChainsTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Compiler.QueryChains

  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.QueryChains.Module1
  alias Hologram.Test.Fixtures.Compiler.QueryChains.Module2

  defp chains(module, function, arity) do
    {_visibility, clauses} =
      module
      |> IR.for_module()
      |> IR.aggregate_module_funs()
      |> Map.new()
      |> Map.fetch!({function, arity})

    collect(clauses, {module, function, arity})
  end

  # A test that a query passes means nothing when no chain was collected to check, so one is.
  defp validate_all!(module, function, arity) do
    collected = chains(module, function, arity)

    assert collected != [],
           "no query chain was collected from #{inspect(module)}.#{function}/#{arity}"

    # A chain whose root is no entity type passes without its stages being checked.
    assert Enum.all?(collected, &Hologram.Reflection.entity?(&1.root, nil)),
           "a query chain from #{inspect(module)}.#{function}/#{arity} has no entity type as its root"

    Enum.each(collected, &validate!(&1, nil))
  end

  defp source_line(module, needle) do
    module
    |> Hologram.Reflection.source_path()
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, needle))
    |> Kernel.+(1)
  end

  describe "collect/2" do
    test "collects a chain written from an entity module, its pinned value standing in" do
      assert [%{root: Hologram.Test.Fixtures.Entity.Module2, steps: steps}] =
               chains(Module1, :valid, 1)

      assert [
               {:filter, [[a: {:==, true}, b: {:>=, %Hologram.Query.Placeholder{name: :min_b}}]],
                _filter_line},
               {:sort, [:c], _sort_line},
               {:take, [5], _take_line}
             ] = steps
    end

    test "ends a chain at a stage whose whole predicate list only the run knows" do
      assert [%{steps: []}] = chains(Module1, :pinned_predicates, 1)
    end

    test "collects no chain for a query built from a variable" do
      assert chains(Module1, :through_variable, 1) == []
    end

    test "collects no chain for a query built in a helper" do
      assert chains(Module1, :through_helper, 0) == []
    end

    test "collects no chain for a query built in a reduce" do
      assert chains(Module1, :through_reduce, 1) == []
    end
  end

  describe "validate!/2" do
    test "passes a query the stages and the checks take" do
      assert validate_all!(Module1, :valid, 1) == :ok
    end

    test "refuses a mistake in a stage in the stage's own words, at its line" do
      error =
        assert_raise Hologram.CompileError, fn ->
          validate_all!(Module1, :unknown_attribute, 0)
        end

      assert error.message =~
               ~r/^the query in Hologram\.Test\.Fixtures\.Compiler\.QueryChains\.Module1\.unknown_attribute\/0 builds an invalid query - .*nonexistent/

      assert error.line == source_line(Module1, "|> sort(nonexistent)")
    end

    test "refuses an ordering operator beside a pinned value on an attribute with no order" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query/, fn ->
        validate_all!(Module1, :pinned_ordering, 1)
      end
    end

    test "refuses a mistyped value beside a pinned one in a disjunction" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query - 5/, fn ->
        validate_all!(Module1, :pinned_beside_mistyped, 1)
      end
    end

    test "refuses a check's mistake at the stage making it" do
      error =
        assert_raise Hologram.CompileError, fn ->
          validate_all!(Module1, :server_only_spread, 0)
        end

      assert error.line == source_line(Module1, "|> filter(token == \"x\")")
    end

    test "passes a derived field's sort a later stage replaces" do
      assert validate_all!(Module2, :__derived_replaced_sort__, 0) == :ok
    end

    test "passes a derived field's sort a count drops" do
      assert validate_all!(Module2, :__derived_counted_secrets__, 0) == :ok
    end

    test "passes a derived field's sort a stage after the cut replaces" do
      assert validate_all!(Module2, :__derived_sorted_again_after_cut__, 1) == :ok
    end

    test "refuses a derived field's sort no stage after the cut replaces" do
      assert_raise Hologram.CompileError, ~r/filters or sorts on server_only attributes/, fn ->
        validate_all!(Module2, :__derived_sorted_before_cut__, 1)
      end
    end

    test "refuses the sort of a derived field's body of several expressions, at the sort" do
      error =
        assert_raise Hologram.CompileError, fn ->
          validate_all!(Module2, :__derived_spread_secrets__, 0)
        end

      assert error.message =~ ~r/filters or sorts on server_only attributes/
      # The sort is the body's fifth line after the declaration.
      assert error.line == source_line(Module2, "derived :spread_secrets") + 5
    end

    test "refuses the sort of a derived field's branch, at the sort" do
      error =
        assert_raise Hologram.CompileError, fn ->
          validate_all!(Module2, :__derived_branch_secrets__, 1)
        end

      assert error.message =~
               ~r/derived field :branch_secrets in .+ filters or sorts on server_only attributes/

      assert error.line == source_line(Module2, "derived :branch_secrets") + 2
    end

    test "refuses the sort of a derived field's cond clause of several expressions" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :cond_secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_cond_secrets__, 1) end
    end

    test "refuses the sort of a derived field's with else clause" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :with_secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_with_secrets__, 1) end
    end

    test "refuses the sort of a derived field's try rescue clause" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :try_secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_try_secrets__, 0) end
    end

    test "refuses the sort of a branch handed straight to the database" do
      assert_raise Hologram.CompileError, ~r/filters or sorts on server_only attributes/, fn ->
        validate_all!(Module1, :read_branch_secret, 1)
      end
    end

    test "refuses the sort of a derived field's branch a later stage keeps" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :taken_branch_secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_taken_branch_secrets__, 1) end
    end

    test "passes the sort of a derived field's branch a later stage replaces" do
      assert validate_all!(Module2, :__derived_sorted_branch_again__, 1) == :ok
    end

    test "passes the sort of a derived field's branch a later count drops" do
      assert validate_all!(Module2, :__derived_counted_branch__, 1) == :ok
    end

    test "refuses the sort of a query a derived field assigns as its result" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :assigned_secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_assigned_secrets__, 0) end
    end

    test "refuses the sort of a query assigned as it's handed to the database" do
      assert_raise Hologram.CompileError, ~r/filters or sorts on server_only attributes/, fn ->
        validate_all!(Module1, :read_assigned_secret, 0)
      end
    end

    test "passes a sort in a derived field's case condition, which a later stage can replace" do
      assert validate_all!(Module2, :__derived_sorted_condition__, 0) == :ok
    end

    test "passes a sort on a server-only attribute of a query in an anonymous function" do
      assert validate_all!(Module1, :sorted_secret_in_fun, 0) == :ok
    end

    test "checks the stages after a pinned sort spec" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query - .*nonexistent/, fn ->
        validate_all!(Module1, :pinned_sort, 1)
      end
    end

    test "refuses a range written as a literal on an attribute it can't compare with" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query/, fn ->
        validate_all!(Module1, :mistyped_range, 0)
      end
    end

    test "passes a list of operators beside a pinned one" do
      assert validate_all!(Module1, :pinned_operator, 1) == :ok
    end

    test "refuses a pinned struct value its attribute can't hold" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query/, fn ->
        validate_all!(Module1, :pinned_date, 0)
      end
    end

    test "refuses a literal sort spec the stage doesn't take" do
      assert_raise Hologram.CompileError, ~r/builds an invalid query/, fn ->
        validate_all!(Module1, :string_sort, 0)
      end
    end

    test "refuses a derived field's own sort on a server-only attribute" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :secrets in .+ filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module2, :__derived_secrets__, 0) end
    end

    test "refuses a sort on a server-only attribute of a query handed straight to the database" do
      assert_raise Hologram.CompileError, ~r/filters or sorts on server_only attributes/, fn ->
        validate_all!(Module1, :read_sorted_secret, 0)
      end
    end

    test "passes a sort on a server-only attribute of a query handed on, which can be sorted again" do
      assert validate_all!(Module1, :sorted_secret_handed_on, 0) == :ok
    end

    test "passes a list of operators holding a pinned value" do
      assert validate_all!(Module1, :pinned_operator_list, 1) == :ok
    end

    test "tells a refusal of a chain cut at its first stage at that stage's line" do
      error =
        assert_raise Hologram.CompileError, fn -> validate_all!(Module1, :dead_cut, 1) end

      assert error.line == source_line(Module1, "def dead_cut(predicates)")
    end

    # The run hands the list its alternatives or the quantifier its source and condition, which
    # the build can't stand in for, so the chain ends at the stage.
    test "passes a pinned predicate list holding alternatives or a quantifier only the run knows" do
      for function <- [:pinned_alternatives, :pinned_any, :pinned_all, :pinned_none] do
        assert validate_all!(Module1, function, 1) == :ok
      end
    end

    # An attribute may be named or, and a comparison of it through an operator is read as any other
    # attribute's.
    test "checks a comparison of an attribute named like alternatives" do
      assert_raise Hologram.CompileError,
                   ~r/builds an invalid query - unknown attribute :or/,
                   fn ->
                     validate_all!(Module1, :literal_or, 0)
                   end
    end

    test "refuses an unknown operator whose operand only the run knows" do
      assert_raise Hologram.CompileError,
                   ~r/builds an invalid query - unknown operator :typo/,
                   fn ->
                     validate_all!(Module1, :typo_operator, 1)
                   end
    end

    # Alternatives are a list of lists, so a list of plain values is a membership in an attribute
    # named or, as the stages read it.
    test "checks a membership filter on an attribute named like alternatives" do
      assert_raise Hologram.CompileError,
                   ~r/builds an invalid query - unknown attribute :or/,
                   fn ->
                     validate_all!(Module1, :membership_or, 0)
                   end
    end

    # A quantifier's condition is a list, so an operator tuple is a comparison of an attribute named
    # any, as the stages read it.
    test "checks a comparison through an operator of an attribute named like a quantifier" do
      assert_raise Hologram.CompileError,
                   ~r/builds an invalid query - unknown attribute :any/,
                   fn ->
                     validate_all!(Module1, :operator_any, 0)
                   end
    end

    test "passes the steps before one only the run knows" do
      assert [%{steps: [{:take, [5], _line}]}] = chains(Module1, :take_before_pinned, 1)
      assert validate_all!(Module1, :take_before_pinned, 1) == :ok
    end

    test "refuses a filter on a server-only attribute" do
      assert_raise Hologram.CompileError,
                   ~r/the query in .+server_only\/0 filters or sorts on server_only attributes/,
                   fn -> validate_all!(Module1, :server_only, 0) end
    end

    test "refuses a query over a type no rule lets anyone read" do
      assert_raise Hologram.CompileError,
                   ~r/reads Hologram\.Test\.Fixtures\.Entity\.Module1, which declares no allow lines/,
                   fn ->
                     validate_all!(Module1, :dead, 0)
                   end
    end

    test "refuses a claim of trust" do
      assert_raise Hologram.CompileError, ~r/claims the server's authority with trust\(\)/, fn ->
        validate_all!(Module1, :trusted, 0)
      end
    end

    test "names a derived field by its name" do
      assert_raise Hologram.CompileError,
                   ~r/derived field :rows in Hologram\.Test\.Fixtures\.Compiler\.QueryChains\.Module2 builds an invalid query/,
                   fn -> validate_all!(Module2, :__derived_rows__, 0) end
    end
  end
end
