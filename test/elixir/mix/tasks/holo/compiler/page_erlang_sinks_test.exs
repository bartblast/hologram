defmodule Mix.Tasks.Holo.Compiler.PageErlangSinksTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.PageErlangSinks, as: Task

  test "run/1" do
    arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageMfaCascades.Module1"

    output = capture_io(fn -> Task.run([arg]) end)

    assert output =~ ~r/\d+ Erlang MFA sinks for/
    assert output =~ ~r/:\w+\.\w+\/\d+ - \d+ MFAs reaching/
  end
end
