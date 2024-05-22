defmodule Hologram.Socket do
  use Phoenix.Socket

  channel "hologram", Hologram.Socket.Channel, websocket: true, longpoll: true

  @impl Phoenix.Socket
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl Phoenix.Socket
  def id(_socket), do: nil
end
