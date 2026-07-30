defmodule Hologram.ExJsConsistency.Elixir.CodeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/code_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  describe "ensure_compiled/1" do
    test "compiled module" do
      assert Code.ensure_compiled(String.Chars) == {:module, String.Chars}
    end

    test "not compiled, non-existing module" do
      assert Code.ensure_compiled(MyModule) == {:error, :nofile}
    end

    test "raises FunctionClauseError if the argument is not an atom" do
      expected_msg =
        build_function_clause_error_msg("Code.ensure_compiled/1", [1], [
          "def ensure_compiled(module) when -is_atom(module)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        1
        |> wrap_term()
        |> Code.ensure_compiled()
      end
    end

    test "error frame carries args" do
      module = wrap_term(1)

      top_frame =
        try do
          Code.ensure_compiled(module)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Elixir code inside code.ex, so its frame
      # location also carries the corresponding file and line, which the
      # client doesn't mirror.
      assert {Code, :ensure_compiled, [1], location} = wrap_term(top_frame)
      assert location[:error_info] == nil
    end
  end

  describe "ensure_loaded/1" do
    test "loaded module" do
      assert Code.ensure_loaded(String.Chars) == {:module, String.Chars}
    end

    test "not loaded, non-existing module" do
      assert Code.ensure_loaded(MyModule) == {:error, :nofile}
    end

    test "raises FunctionClauseError if the argument is not an atom" do
      expected_msg =
        build_function_clause_error_msg("Code.ensure_loaded/1", [1], [
          "def ensure_loaded(module) when -is_atom(module)-"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        1
        |> wrap_term()
        |> Code.ensure_loaded()
      end
    end

    test "error frame carries args" do
      module = wrap_term(1)

      top_frame =
        try do
          Code.ensure_loaded(module)
        rescue
          _error -> hd(wrap_term(__STACKTRACE__))
        end

      # The server implements this function in Elixir code inside code.ex, so its frame
      # location also carries the corresponding file and line, which the
      # client doesn't mirror.
      assert {Code, :ensure_loaded, [1], location} = wrap_term(top_frame)
      assert location[:error_info] == nil
    end
  end
end
