defmodule Hologram.Socket.Channel do
  @moduledoc false

  use Phoenix.Channel

  @impl Phoenix.Channel
  def join("hologram", _payload, socket) do
    {:ok, socket}
  end
end
