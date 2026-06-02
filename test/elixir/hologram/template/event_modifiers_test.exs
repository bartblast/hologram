defmodule Hologram.Template.EventModifiersTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Template.EventModifiers

  alias Hologram.TemplateSyntaxError

  describe "keyboard_event?/1" do
    test "returns true for keyboard event base names" do
      assert keyboard_event?("$key_down")
    end

    test "returns false for non-keyboard event base names" do
      refute keyboard_event?("$click")
    end
  end

  describe "parse/1" do
    test "single named key" do
      assert parse(["enter"]) == [{:key, ["enter"]}]
    end

    test "single character key" do
      assert parse(["k"]) == [{:key, ["k"]}]
    end

    test "uppercase key is downcased" do
      assert parse(["K"]) == [{:key, ["k"]}]
    end

    test "modifier combined with a key" do
      assert parse(["ctrl+k"]) == [{:key, ["ctrl", "k"]}]
    end

    test "multiple modifiers combined with a key" do
      assert parse(["ctrl+shift+k"]) == [{:key, ["ctrl", "shift", "k"]}]
    end

    test "named key is normalized to its event.key form" do
      assert parse(["arrow_up"]) == [{:key, ["arrowup"]}]
    end

    test "single underscore key is kept verbatim, not treated as a separator" do
      assert parse(["_"]) == [{:key, ["_"]}]
    end

    test "space resolves to the literal space key" do
      assert parse(["space"]) == [{:key, [" "]}]
    end

    test "function key" do
      assert parse(["f5"]) == [{:key, ["f5"]}]
    end

    test "multiple segments become multiple key filters" do
      assert parse(["enter", "ctrl+k"]) == [{:key, ["enter"]}, {:key, ["ctrl", "k"]}]
    end

    test "raises for an unknown key with a suggestion" do
      assert_raise TemplateSyntaxError,
                   ~s(unknown keyboard key "entr". Did you mean "enter"?),
                   fn -> parse(["entr"]) end
    end

    test "raises for more than one key in a single filter" do
      assert_raise TemplateSyntaxError,
                   ~s(keyboard key filter "k+j" specifies more than one key),
                   fn -> parse(["k+j"]) end
    end

    test "raises for an empty segment" do
      assert_raise TemplateSyntaxError,
                   "keyboard key filter must not be empty",
                   fn -> parse([""]) end
    end

    test "raises for an empty token in a combination" do
      assert_raise TemplateSyntaxError,
                   "keyboard key filter must not be empty",
                   fn -> parse(["ctrl+"]) end
    end
  end
end
