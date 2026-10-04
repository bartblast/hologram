defmodule Mix.Tasks.Holo.Compiler.RuntimeToMfaPathsTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.RuntimeToMfaPaths, as: Task

  describe "run/1" do
    test "destination included in the runtime" do
      output = capture_io(fn -> Task.run(["{Enum, :reduce, 3}"]) end)

      expected =
        normalize_newlines("""
        {Enum, :reverse, 1} -> {Enum, :reduce, 3}
        [{Enum, :reverse, 1}, {Enum, :reduce, 3}]
        """)

      assert String.contains?(output, expected)
    end

    test "destination not included in the runtime" do
      output =
        capture_io(fn ->
          Task.run([
            "{String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12, :to_string, 1}"
          ])
        end)

      assert output == ""
    end
  end
end
