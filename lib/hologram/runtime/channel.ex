# DEFER: test
defmodule Hologram.Channel do
  use Phoenix.Channel

  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  def handle_in("command", %{"command" => command, "context" => context} = request, socket) do
    IO.inspect(request)
    result = "some command result"
    {:reply, {:ok, result}, socket}
  end
end
