defmodule Hologram.Component.NotComputedTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Component.NotComputed

  test "inspects as the field it stands for and why" do
    assert inspect(%NotComputed{field: :shown}) ==
             "#Hologram.Component.NotComputed<:shown reads state, so it's computed after init>"
  end
end
