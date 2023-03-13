defmodule Hologram.Runtime.ComponentTest do
  use Hologram.Test.UnitCase, async: true

  test "is_component?/0" do
    module = Hologram.Test.Fixtures.Runtime.Component.Module1
    assert module.is_component?()
  end
end
