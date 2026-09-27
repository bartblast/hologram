defmodule Hologram.Compiler.DataFlow.Rules.AshTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow.Rules.Ash

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow

  # Hologram's own tests run without Ash; the rules are tested with it in the ecosystem tests app
  # (test/ecosystem).

  test "available?/0 is false without Ash" do
    refute available?()
  end

  test "summary/2 answers nothing" do
    flow = DataFlow.start(PLT.start(), PLT.start())

    assert summary({String, :upcase, 1}, flow) == nil
  end
end
