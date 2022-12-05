defmodule Hologram.Compiler.EnvTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Env

  test "init/0" do
    assert %Macro.Env{} = Env.init()
  end
end
