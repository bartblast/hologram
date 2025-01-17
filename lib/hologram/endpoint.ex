defmodule Hologram.Endpoint do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Hologram.Endpoint, only: [hologram_socket: 0]
    end
  end

  defmacro hologram_socket do
    quote do
      socket "/hologram", Hologram.Socket,
        websocket: [check_origin: true],
        longpoll: [check_origin: true]
    end
  end
end
