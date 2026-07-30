defmodule Hologram.ExJsConsistency.Elixir.TaskTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/task_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "await/1" do
    # The attempted function clauses come from the clause heads the runtime script
    # registers at bundle load, which unit tests don't run, so the JavaScript twin
    # asserts the message without them.
    test "raises FunctionClauseError if the arg is not a Task struct" do
      expected_msg =
        build_function_clause_error_msg("Task.await/2", [123, 5000], [
          "def await(-%Task{ref: ref, owner: owner} = task-, timeout) when -timeout == :infinity- or is_integer(timeout) and timeout >= 0"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        123
        |> wrap_term()
        |> Task.await()
      end
    end

    test "error frame carries the await/2 args" do
      arg = wrap_term(123)

      top_frame =
        try do
          Task.await(arg)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Elixir code inside task.ex, so its frame
      # location also carries the corresponding file and line, which the
      # client doesn't mirror.
      assert {Task, :await, [123, 5000], location} = wrap_term(top_frame)
      assert location[:error_info] == nil
    end
  end
end
