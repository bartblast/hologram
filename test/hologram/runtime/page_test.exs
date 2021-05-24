defmodule Hologram.PageTest do
  use Hologram.TestCase, async: true
  alias Hologram.Page

  test "update/3" do
    assert Page.update(%{a: 1}, :b, 2) == %{a: 1, b: 2}
  end
end
