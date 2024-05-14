defmodule Hologram.SocketTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Socket

  test "connect/3" do
    assert connect(:dummy_params, :dummy_socket, :dummy_connect_info) == {:ok, :dummy_socket}
  end

  test "id/1" do
    assert id(:dummy_socket) == nil
  end
end
