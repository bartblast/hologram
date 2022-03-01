defmodule Hologram.Runtime.LayoutTest do
  use Hologram.Test.UnitCase, async: true

  test "is_layout?/0" do
    module = Hologram.Test.Fixtures.Runtime.Layout.Module1
    assert module.is_layout?()
  end
end
