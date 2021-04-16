defmodule Hologram.Transpiler.HelpersTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Helpers

  test "module_name/1" do
    assert Helpers.module_name([:Abc, :Bcd]) == "Abc.Bcd"
  end
end
