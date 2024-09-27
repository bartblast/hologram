defmodule Hologram.ExJsConsistency.Elixir.IOTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/elixir/io_test.mjs
  Always update both together.
  """

  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO

  @moduletag :consistency

  describe "inspect/1" do
    test "delegates to inspect/2" do
      output =
        capture_io(fn ->
          # credo:disable-for-next-line Credo.Check.Warning.IoInspect
          assert IO.inspect(true) == true
        end)

      assert output == "true\n"
    end
  end

  describe "inspect/2" do
    test "delegates to inspect/3" do
      output =
        capture_io(fn ->
          # credo:disable-for-next-line Credo.Check.Warning.IoInspect
          assert IO.inspect(%{b: 2, a: 1}, custom_options: [sort_maps: true]) == %{
                   a: 1,
                   b: 2
                 }
        end)

      assert output == "%{a: 1, b: 2}\n"
    end
  end

  # Also see interpreter "inspect" consistency tests
  describe "inspect/3" do
    test "outputs inspected term to the :stdio device" do
      output =
        capture_io(fn ->
          # credo:disable-for-next-line Credo.Check.Warning.IoInspect
          assert IO.inspect(:stdio, %{b: 2, a: 1}, custom_options: [sort_maps: true]) == %{
                   a: 1,
                   b: 2
                 }
        end)

      assert output == "%{a: 1, b: 2}\n"
    end

    # Client error message is intentionally different than server error message.
    test "raises FunctionClauseError if the first arg is not an atom or a pid" do
      expected_msg =
        build_function_clause_error_msg("IO.inspect/3", [123, :abc, []], [
          "def inspect(device, item, opts) when (-is_atom(device)- or -is_pid(device)-) and is_list(opts)"
        ])

      assert_error FunctionClauseError, expected_msg, fn ->
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(123, :abc, [])
      end
    end
  end
end
