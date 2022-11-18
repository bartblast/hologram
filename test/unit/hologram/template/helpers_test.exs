defmodule Hologram.Template.HelpersTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Template.Helpers

  describe "tag_type/1" do
    test "element" do
      assert Helpers.tag_type("div") == :element
    end

    test "component" do
      assert Helpers.tag_type("MyComponent") == :component
    end
  end
end
