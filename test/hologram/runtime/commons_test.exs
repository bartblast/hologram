defmodule Hologram.Runtime.CommonsTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Runtime.Commons

  test "sigil_H/2" do
    assert Commons.sigil_H(" \ntest \n", []) == "test"
  end

  test "update/3" do
    assert Commons.update(%{a: 1}, :b, 2) == %{a: 1, b: 2}
  end
end
