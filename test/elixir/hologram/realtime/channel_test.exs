defmodule Hologram.Realtime.ChannelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.Channel

  describe "validate!/1" do
    test "accepts an atom" do
      assert validate!(:notifications) == :notifications
    end

    test "accepts a tuple" do
      assert validate!({:doc, "abc", "v2"}) == {:doc, "abc", "v2"}
    end

    test "rejects a value that isn't an identifier with a hint" do
      assert_error ArgumentError,
                   "a channel must be an identifier, like :search or {:message, 42}, got: {:room, nil} - nil, true and false can't be in an identifier",
                   fn -> validate!({:room, nil}) end
    end

    test "rejects a value that isn't an identifier without a hint" do
      assert_error ArgumentError,
                   ~s(a channel must be an identifier, like :search or {:message, 42}, got: "my-channel"),
                   fn -> validate!("my-channel") end
    end

    test "rejects a tuple with a true value" do
      assert_error ArgumentError,
                   "a channel must be an identifier, like :search or {:message, 42}, got: {:room, true} - nil, true and false can't be in an identifier",
                   fn -> validate!({:room, true}) end
    end

    test "rejects nil" do
      assert_error ArgumentError,
                   "a channel must be an identifier, like :search or {:message, 42}, got: nil - nil, true and false can't be in an identifier",
                   fn -> validate!(nil) end
    end
  end
end
