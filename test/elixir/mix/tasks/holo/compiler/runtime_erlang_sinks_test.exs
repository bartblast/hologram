defmodule Mix.Tasks.Holo.Compiler.RuntimeErlangSinksTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.RuntimeErlangSinks, as: Task

  test "run/1" do
    output = capture_io(fn -> Task.run([]) end)

    assert output =~ ~r/\d+ Erlang MFA sinks in runtime:/
    assert output =~ ~r/:\w+\.\w+\/\d+ - \d+ MFAs reaching/
  end
end
