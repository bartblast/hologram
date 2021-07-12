# DEFER: test
defmodule Hologram.Channel do
  use Phoenix.Channel

  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  def handle_in("command", {command, params}, socket) do
    IO.inspect("command received...")
    {:reply, :ok, socket}
  end
end
