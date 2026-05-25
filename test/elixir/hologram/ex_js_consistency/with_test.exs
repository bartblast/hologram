defmodule Hologram.ExJsConsistency.WithTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/interpreter_test.mjs (with() section)
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  test "evaluates the body when there are no clauses" do
    result = with do: nil

    assert result == nil
  end

  test "returns the unmatched value when there are no else clauses" do
    a = :ok

    result =
      with :error <- a do
        :body
      end

    assert result == :ok
  end

  describe "match clauses" do
    test "returns the body result for a single matching clause" do
      a = :ok

      result =
        with b <- a do
          {a, b}
        end

      assert result == {:ok, :ok}
    end

    test "returns the body result for multiple matching clauses" do
      a = :ok

      result =
        with b <- a,
             :ok <- b do
          {a, b}
        end

      assert result == {:ok, :ok}
    end

    test "returns the body result for a clause with a passing guard" do
      a = :ok

      result =
        with b when b == :ok <- a do
          {a, b}
        end

      assert result == {:ok, :ok}
    end
  end

  describe "bare clauses" do
    test "evaluates a bare expression clause" do
      a = :ok

      result =
        with b = a do
          {a, b}
        end

      assert result == {:ok, :ok}
    end

    test "evaluates multiple bare expression clauses" do
      a = :ok

      result =
        with b = a,
             c = b do
          {a, b, c}
        end

      assert result == {:ok, :ok, :ok}
    end

    test "raises a MatchError when a bare clause fails to match" do
      # wrap_term/1 keeps the compiler from flagging `:error = a` as a pattern that
      # will never match (the bare `=` is type-checked at compile time).
      a = wrap_term(:ok)

      assert_error MatchError, "no match of right hand side value: :ok", fn ->
        with :error = a do
          :body
        end
      end
    end
  end

  describe "else clauses" do
    test "routes a failed match to a single else clause" do
      a = :ok

      result =
        with :error <- a do
          :body
        else
          :ok -> :match
        end

      assert result == :match
    end

    test "selects the matching clause among multiple else clauses" do
      a = :ok

      result =
        with :error <- a do
          :body
        else
          :a -> :first
          :ok -> :second
          :c -> :third
        end

      assert result == :second
    end

    test "selects a guarded else clause when its guard passes" do
      a = :ok

      result =
        with :error <- a do
          :body
        else
          e when e == :ok -> {:guarded, e}
        end

      assert result == {:guarded, :ok}
    end

    test "routes a failed guard to the else clauses" do
      a = :ok

      result =
        with b when b == :no <- a do
          :body
        else
          :ok -> {:error, :nomatch}
        end

      assert result == {:error, :nomatch}
    end

    test "raises WithClauseError when no else clause matches" do
      a = :ok

      assert_error WithClauseError, "no with clause matching: :ok", fn ->
        with :error <- a do
          :body
        else
          :other -> nil
        end
      end
    end
  end

  describe "variable scoping" do
    test "does not leak assignments into the original context" do
      a = :ok

      with b <- a do
        a = 2
        {a, b}
      end

      assert a == :ok
    end

    test "evaluates else clauses in the original context" do
      x = :original
      a = :ok

      result =
        with x <- a,
             :fail <- :mismatch do
          x
        else
          _fallback -> x
        end

      assert result == :original
    end

    test "lets a later clause shadow an earlier binding" do
      result =
        with a <-
               (
                 b = 1
                 _var = b
                 1
               ),
             b <- 2 do
          a + b
        end

      assert result == 3
    end
  end
end
