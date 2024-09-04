defmodule Mix.Tasks.Holo.Compiler.ExRuntimeMfasTest do
  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.ExRuntimeMfas, as: Task

  test "run/1" do
    output = capture_io(fn -> Task.run([]) end)

    assert output =~ ~r/^[1-9][0-9]* MFAs found:\n\n\[.+\]\n$/s
    refute output =~ ~r/\{Kernel, :inspect, 2\}/
  end
end
