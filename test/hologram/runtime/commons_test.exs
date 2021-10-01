defmodule Hologram.Runtime.CommonsTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Runtime.Commons

  test "sigil_H/2" do
    assert Commons.sigil_H(" \ntest \n", []) == "test"
  end
end
