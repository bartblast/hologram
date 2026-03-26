defmodule Mix.Tasks.Holo.Compiler.RuntimeMfaCascadesTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.RuntimeMfaCascades, as: Task

  test "run/1" do
    output = capture_io(fn -> Task.run([]) end)

    assert output =~ ~r/\d+ edges to module vertices:/
    assert output =~ ~r/\{.+, :.+, \d+\} -> .+ \(\d+ MFAs reachable\)/
  end
end
