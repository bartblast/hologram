defmodule Hologram.Runtime.CommonsTest do
  use Hologram.TestCase, async: true
  alias Hologram.Runtime.Commons

  test "sigil_H/2" do
    assert Commons.sigil_H("test", []) == "test"
  end
end
