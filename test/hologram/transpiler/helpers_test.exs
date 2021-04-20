defmodule Hologram.Transpiler.HelpersTest do
  use ExUnit.Case, async: true
  alias Hologram.Transpiler.Helpers

  test "class_name/1" do
    assert Helpers.class_name([:Abc, :Bcd]) == "AbcBcd"
  end

  test "fully_qualified_module/1" do
    result = Helpers.fully_qualified_module([:Hologram, :Transpiler, :HelpersTest])
    expected = Elixir.Hologram.Transpiler.HelpersTest
    assert result == expected
  end

  test "module_name/1" do
    assert Helpers.module_name([:Abc, :Bcd]) == "Abc.Bcd"
  end

  test "module_name_atom/1" do
    assert Helpers.module_name_atom([:Abc, :Bcd]) == :"Abc.Bcd"
  end
end
