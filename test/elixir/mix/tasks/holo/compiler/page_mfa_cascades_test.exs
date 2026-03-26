defmodule Mix.Tasks.Holo.Compiler.PageMfaCascadesTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.PageMfaCascades, as: Task

  test "run/1" do
    arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageMfaCascades.Module1"

    output = capture_io(fn -> Task.run([arg]) end)

    assert output =~ ~r/\d+ edges to module vertices for/
    assert output =~ ~r/\{.+, :.+, \d+\} -> .+ \(\d+ MFAs reachable\)/
  end
end
