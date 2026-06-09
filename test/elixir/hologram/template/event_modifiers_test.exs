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

  describe "parse/2 allow_default modifier" do
    test "on a non-keyboard event" do
      assert parse("$click", ["allow_default"]) == %{allow_default: true}
    end

    test "on a keyboard event" do
      assert parse("$key_down", ["allow_default"]) == %{allow_default: true}
    end
  end

  describe "parse/2 debounce modifier" do
    test "on a non-keyboard event" do
      assert parse("$change", ["debounce(300)"]) == %{debounce: 300}
    end

    test "on a keyboard event" do
      assert parse("$key_down", ["debounce(300)"]) == %{debounce: 300}
    end

    test "bare debounce takes the default window" do
      assert parse("$change", ["debounce"]) == %{debounce: 250}
    end

    test "large value has no upper bound" do
      assert parse("$change", ["debounce(60000)"]) == %{debounce: 60_000}
    end

    test "raises for a missing value" do
      assert_raise TemplateSyntaxError,
                   ~s'debounce modifier "debounce()" requires a positive integer of milliseconds',
                   fn -> parse("$change", ["debounce()"]) end
    end

    test "raises for a non-integer value" do
      assert_raise TemplateSyntaxError,
                   ~s'debounce modifier "debounce(abc)" requires a positive integer of milliseconds',
                   fn -> parse("$change", ["debounce(abc)"]) end
    end

    test "raises for a negative value" do
      assert_raise TemplateSyntaxError,
                   ~s'debounce modifier "debounce(-5)" requires a positive integer of milliseconds',
                   fn -> parse("$change", ["debounce(-5)"]) end
    end

    test "raises for a zero value" do
      assert_raise TemplateSyntaxError,
                   ~s'debounce modifier "debounce(0)" requires a positive integer of milliseconds',
                   fn -> parse("$change", ["debounce(0)"]) end
    end

    test "raises for more than one debounce modifier" do
      assert_raise TemplateSyntaxError,
                   "an event binding may include at most one debounce modifier",
                   fn -> parse("$click", ["debounce(100)", "debounce(500)"]) end
    end
  end

  describe "parse/2 key filter modifier" do
    test "single named key" do
      assert parse("$key_down", ["enter"]) == %{key: [["enter"]]}
    end

    test "single character key" do
      assert parse("$key_down", ["k"]) == %{key: [["k"]]}
    end

    test "uppercase key is downcased" do
      assert parse("$key_down", ["K"]) == %{key: [["k"]]}
    end

    test "modifier combined with a key" do
      assert parse("$key_down", ["ctrl+k"]) == %{key: [["ctrl", "k"]]}
    end

    test "multiple modifiers combined with a key" do
      assert parse("$key_down", ["ctrl+shift+k"]) == %{key: [["ctrl", "shift", "k"]]}
    end

    test "named key is normalized to its event.key form" do
      assert parse("$key_down", ["arrow_up"]) == %{key: [["arrowup"]]}
    end

    test "symbol alias resolves to its event.key char" do
      assert parse("$key_down", ["slash"]) == %{key: [["/"]]}
    end

    test "modifier combined with a symbol alias" do
      assert parse("$key_down", ["ctrl+slash"]) == %{key: [["ctrl", "/"]]}
    end

    test "space resolves to the literal space key" do
      assert parse("$key_down", ["space"]) == %{key: [[" "]]}
    end

    test "function key" do
      assert parse("$key_down", ["f5"]) == %{key: [["f5"]]}
    end

    test "multiple segments become multiple key filters" do
      assert parse("$key_down", ["enter", "ctrl+k"]) == %{key: [["enter"], ["ctrl", "k"]]}
    end

    test "raises for an unknown key with a suggestion" do
      assert_raise TemplateSyntaxError,
                   ~s'unknown keyboard key "entr". Did you mean "enter"?',
                   fn -> parse("$key_down", ["entr"]) end
    end

    test "raises for more than one key in a single filter" do
      assert_raise TemplateSyntaxError,
                   ~s'keyboard key filter "k+j" specifies more than one key',
                   fn -> parse("$key_down", ["k+j"]) end
    end

    test "raises for a filter with only a modifier" do
      assert_raise TemplateSyntaxError,
                   ~s'keyboard key filter "ctrl" specifies no key',
                   fn -> parse("$key_down", ["ctrl"]) end
    end

    test "raises for a filter with only modifiers" do
      assert_raise TemplateSyntaxError,
                   ~s'keyboard key filter "shift+alt" specifies no key',
                   fn -> parse("$key_down", ["shift+alt"]) end
    end

    test "raises for an empty segment" do
      assert_raise TemplateSyntaxError,
                   "keyboard key filter must not be empty",
                   fn -> parse("$key_down", [""]) end
    end

    test "raises for an empty token in a combination" do
      assert_raise TemplateSyntaxError,
                   "keyboard key filter must not be empty",
                   fn -> parse("$key_down", ["ctrl+"]) end
    end

    test "raises for a raw symbol that has an alias" do
      assert_raise TemplateSyntaxError,
                   ~s'use "semicolon" instead of the literal ";" in a keyboard key filter',
                   fn -> parse("$key_down", [";"]) end
    end

    test "raises for a raw symbol without an alias" do
      assert_raise TemplateSyntaxError,
                   ~s'the "_" key has no keyboard key filter alias; match it in the action handler',
                   fn -> parse("$key_down", ["_"]) end
    end

    test "raises for a misspelled alias with a suggestion" do
      assert_raise TemplateSyntaxError,
                   ~s'unknown keyboard key "slsh". Did you mean "slash"?',
                   fn -> parse("$key_down", ["slsh"]) end
    end

    test "raises on a non-keyboard event" do
      assert_raise TemplateSyntaxError,
                   ~s'unknown event modifier "enter"',
                   fn -> parse("$change", ["enter"]) end
    end
  end

  describe "parse/2 stop_propagation modifier" do
    test "on a non-keyboard event" do
      assert parse("$click", ["stop_propagation"]) == %{stop_propagation: true}
    end

    test "on a keyboard event" do
      assert parse("$key_down", ["stop_propagation"]) == %{stop_propagation: true}
    end
  end

  describe "parse/2 throttle modifier" do
    test "on a non-keyboard event" do
      assert parse("$mouse_move", ["throttle(100)"]) == %{throttle: 100}
    end

    test "on a keyboard event" do
      assert parse("$key_down", ["throttle(100)"]) == %{throttle: 100}
    end

    test "bare throttle takes the default window" do
      assert parse("$mouse_move", ["throttle"]) == %{throttle: 100}
    end

    test "large value has no upper bound" do
      assert parse("$mouse_move", ["throttle(60000)"]) == %{throttle: 60_000}
    end

    test "raises for a missing value" do
      assert_raise TemplateSyntaxError,
                   ~s'throttle modifier "throttle()" requires a positive integer of milliseconds',
                   fn -> parse("$mouse_move", ["throttle()"]) end
    end

    test "raises for a non-integer value" do
      assert_raise TemplateSyntaxError,
                   ~s'throttle modifier "throttle(abc)" requires a positive integer of milliseconds',
                   fn -> parse("$mouse_move", ["throttle(abc)"]) end
    end

    test "raises for a negative value" do
      assert_raise TemplateSyntaxError,
                   ~s'throttle modifier "throttle(-5)" requires a positive integer of milliseconds',
                   fn -> parse("$mouse_move", ["throttle(-5)"]) end
    end

    test "raises for a zero value" do
      assert_raise TemplateSyntaxError,
                   ~s'throttle modifier "throttle(0)" requires a positive integer of milliseconds',
                   fn -> parse("$mouse_move", ["throttle(0)"]) end
    end

    test "raises for more than one throttle modifier" do
      assert_raise TemplateSyntaxError,
                   "an event binding may include at most one throttle modifier",
                   fn -> parse("$mouse_move", ["throttle(100)", "throttle(200)"]) end
    end
  end

  describe "parse/2 modifier combinations" do
    test "allow_default composes with another modifier" do
      assert parse("$key_down", ["allow_default", "enter"]) ==
               %{allow_default: true, key: [["enter"]]}
    end

    test "debounce composes with another modifier" do
      assert parse("$change", ["debounce(300)", "allow_default"]) ==
               %{allow_default: true, debounce: 300}
    end

    test "a key filter composes with another modifier" do
      assert parse("$key_down", ["enter", "debounce(200)"]) ==
               %{debounce: 200, key: [["enter"]]}
    end

    test "stop_propagation composes with another modifier" do
      assert parse("$click", ["stop_propagation", "allow_default"]) ==
               %{allow_default: true, stop_propagation: true}
    end

    test "throttle composes with another modifier" do
      assert parse("$mouse_move", ["throttle(100)", "allow_default"]) ==
               %{allow_default: true, throttle: 100}
    end

    test "rejects debounce and throttle together" do
      assert_raise TemplateSyntaxError,
                   "an event binding may not combine debounce and throttle modifiers",
                   fn -> parse("$change", ["debounce(300)", "throttle(100)"]) end
    end
  end
end
