defmodule Hologram.Template.HelpersTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Helpers

  describe "tag_type/1" do
    test "element" do
      assert tag_type("div") == :element
    end

    test "component" do
      assert tag_type("MyComponent") == :component
    end
  end
end
