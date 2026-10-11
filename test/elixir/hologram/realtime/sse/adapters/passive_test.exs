defmodule Hologram.Realtime.SSE.Adapters.PassiveTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.SSE.Adapters.Passive

  describe "handle_message/1" do
    test "ignores any message" do
      assert handle_message({:tcp_closed, :dummy_socket}) == :ignore
    end
  end

  describe "watch/1" do
    test "arms nothing" do
      conn = Plug.Test.conn(:get, "/")

      assert watch(conn) == :ok
    end
  end
end
