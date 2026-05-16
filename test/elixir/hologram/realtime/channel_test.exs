defmodule Hologram.Realtime.ChannelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.Channel

  describe "validate!/1" do
    test "accepts a bare atom" do
      assert validate!(:notifications) == :notifications
    end

    test "accepts a 2-tuple with an atom value" do
      assert validate!({:tag, :value}) == {:tag, :value}
    end

    test "accepts a 2-tuple with an integer value" do
      assert validate!({:room, 42}) == {:room, 42}
    end

    test "accepts a 2-tuple with a string value" do
      assert validate!({:room, "lounge"}) == {:room, "lounge"}
    end

    test "accepts a 3+-tuple with mixed primitive values" do
      assert validate!({:doc, "abc", "v2"}) == {:doc, "abc", "v2"}
      assert validate!({:tag, :a, 1, "s"}) == {:tag, :a, 1, "s"}
    end

    test "rejects a bare string" do
      assert_error ArgumentError,
                   "channel must be a bare atom or tagged tuple; got bare string \"my-channel\"",
                   fn -> validate!("my-channel") end
    end

    test "rejects a tuple whose first element is not an atom" do
      assert_error ArgumentError,
                   "channel tuple's first element must be an atom; got {\"room\", 42}",
                   fn -> validate!({"room", 42}) end
    end

    test "rejects a tuple containing a non-primitive value" do
      assert_error ArgumentError,
                   "channel tuple elements after the tag must be primitive (atom, integer, string); got %{a: 1} in {:room, %{a: 1}}",
                   fn -> validate!({:room, %{a: 1}}) end
    end

    test "rejects a 1-tuple" do
      assert_error ArgumentError,
                   "channel tuple must have at least 2 elements; got 1-tuple {:foo}",
                   fn -> validate!({:foo}) end
    end

    test "rejects a non-supported scalar type" do
      assert_error ArgumentError,
                   "channel must be a bare atom or tagged tuple; got 1.5",
                   fn -> validate!(1.5) end
    end
  end
end
