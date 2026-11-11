defmodule Hologram.IdentifierTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Identifier

  @expectation "a thing must be an identifier"

  describe "check/1" do
    test "an atom" do
      assert check(:search) == :ok
    end

    test "a module" do
      assert check(MyApp.Room) == :ok
    end

    test "a tuple with an atom value" do
      assert check({:tag, :value}) == :ok
    end

    test "a tuple with an integer value" do
      assert check({:message, 42}) == :ok
    end

    test "a tuple with a string value" do
      assert check({:room, "lounge"}) == :ok
    end

    test "a tuple with several values of mixed types" do
      assert check({:cell, :a, 1, "b"}) == :ok
    end

    test "nil" do
      assert check(nil) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "true" do
      assert check(true) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "false" do
      assert check(false) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "an empty tuple" do
      assert check({}) ==
               {:error, "an identifier tuple holds an atom and at least one more value"}
    end

    test "a tuple of one atom" do
      assert check({:room}) ==
               {:error, "an identifier tuple holds an atom and at least one more value"}
    end

    test "a tuple of one value that isn't an atom" do
      assert check({1}) ==
               {:error, "an identifier tuple holds an atom and at least one more value"}
    end

    test "a tuple of one nil" do
      assert check({nil}) ==
               {:error, "an identifier tuple holds an atom and at least one more value"}
    end

    test "a tuple whose first element is nil" do
      assert check({nil, 1}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple whose first element is true" do
      assert check({true, 1}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple whose first element is false" do
      assert check({false, 1}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple whose first element is a string" do
      assert check({"room", 42}) == {:error, "an identifier tuple starts with an atom"}
    end

    test "a tuple whose first element is a string and whose value is nil" do
      assert check({"room", nil}) == {:error, "an identifier tuple starts with an atom"}
    end

    test "a tuple with a nil value" do
      assert check({:room, nil}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple with a true value" do
      assert check({:room, true}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple with a false value" do
      assert check({:room, false}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple with a float value" do
      assert check({:room, 1.5}) ==
               {:error,
                "an identifier tuple holds only integers, strings and atoms after its atom"}
    end

    test "a tuple with a map value" do
      assert check({:room, %{a: 1}}) ==
               {:error,
                "an identifier tuple holds only integers, strings and atoms after its atom"}
    end

    test "a tuple with a list value" do
      assert check({:room, [1]}) ==
               {:error,
                "an identifier tuple holds only integers, strings and atoms after its atom"}
    end

    test "a tuple with a tuple value" do
      assert check({:room, {:a, 1}}) ==
               {:error,
                "an identifier tuple holds only integers, strings and atoms after its atom"}
    end

    test "a tuple with a string value that isn't valid UTF-8" do
      assert check({:doc, <<255>>}) == {:error, "strings must be valid UTF-8"}
    end

    test "a tuple with a nil value before a float value" do
      assert check({:room, nil, 1.5}) == {:error, "nil, true and false can't be in an identifier"}
    end

    test "a tuple with a float value before a nil value" do
      assert check({:room, 1.5, nil}) ==
               {:error,
                "an identifier tuple holds only integers, strings and atoms after its atom"}
    end

    test "a string" do
      assert check("room") == {:error, nil}
    end

    test "an integer" do
      assert check(42) == {:error, nil}
    end

    test "a float" do
      assert check(1.5) == {:error, nil}
    end

    test "a list" do
      assert check([:room, 42]) == {:error, nil}
    end

    test "a map" do
      assert check(%{id: 42}) == {:error, nil}
    end

    test "a pid" do
      assert check(self()) == {:error, nil}
    end
  end

  describe "message/3" do
    test "with a hint" do
      assert message(@expectation, {:room, nil}, "nil, true and false can't be in an identifier") ==
               "a thing must be an identifier, got: {:room, nil} - nil, true and false can't be in an identifier"
    end

    test "without a hint" do
      assert message(@expectation, 1.5, nil) == "a thing must be an identifier, got: 1.5"
    end
  end

  describe "validate!/2" do
    test "returns an atom" do
      assert validate!(:search, @expectation) == :search
    end

    test "returns a tuple" do
      assert validate!({:message, 42}, @expectation) == {:message, 42}
    end

    test "raises with the hint for a value with one" do
      assert_error ArgumentError,
                   "a thing must be an identifier, got: {:room, nil} - nil, true and false can't be in an identifier",
                   {Hologram.Identifier, :validate!, [{:room, nil}, @expectation]}
    end

    test "raises without a hint for a value without one" do
      assert_error ArgumentError,
                   ~s(a thing must be an identifier, got: "room"),
                   {Hologram.Identifier, :validate!, ["room", @expectation]}
    end
  end
end
