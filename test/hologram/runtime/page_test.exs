defmodule Hologram.PageTest do
  use ExUnit.Case, async: true
  alias Hologram.Page

  test "sigil_H/2" do
    assert Page.sigil_H("test", []) == "test"
  end

  test "update/3" do
    assert Page.update(%{a: 1}, :b, 2) == %{a: 1, b: 2}
  end
end
