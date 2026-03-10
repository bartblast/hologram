defmodule Hologram.ExJsConsistency.Elixir.TaskTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/task_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "await/1" do
    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the arg is not a Task struct" do
      expected_msg =
        build_function_clause_error_msg("Task.await/2", [123, 5000], [
          "def await(-%Task{ref: ref, owner: owner} = task-, timeout) when -timeout == :infinity- or is_integer(timeout) and timeout >= 0"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        Task.await(123)
      end
    end
  end
end
