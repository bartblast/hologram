defmodule Hologram.ChannelTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Channel

  describe "join/3" do
    test "valid topic name" do
      assert join("hologram", :dummy_payload, :dummy_socket) == {:ok, :dummy_socket}
    end

    test "invalid topic name" do
      assert_raise FunctionClauseError,
                   "no function clause matching in Hologram.Channel.join/3",
                   fn ->
                     join("invalid", :dummy_payload, :dummy_socket)
                   end
    end
  end
end
