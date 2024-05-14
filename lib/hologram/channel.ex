defmodule Hologram.Channel do
  use Phoenix.Channel

  @impl Phoenix.Channel
  def join("hologram", _payload, socket) do
    {:ok, socket}
  end
end
