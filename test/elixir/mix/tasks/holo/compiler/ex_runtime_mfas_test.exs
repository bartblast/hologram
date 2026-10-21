defmodule Mix.Tasks.Holo.Compiler.ExRuntimeMfasTest do
  # async: false - the task builds the call graph of the whole project, which takes a few
  # seconds alone. Run concurrently with the other compiler task tests and the async suite, the
  # builds contend for the runner's cores - on Windows CI they took up to 56 s, and sometimes ran
  # past the 60 s timeout.
  use Hologram.Test.BasicCase, async: false
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.ExRuntimeMfas, as: Task

  test "run/1" do
    output = capture_io(fn -> Task.run([]) end)

    assert output =~ ~r/^[1-9][0-9]* MFAs found:\n\n\[.+\]\n$/s
    refute output =~ ~r/\{Kernel, :inspect, 2\}/
  end
end
