defmodule Hologram.Runtime.Socket do
  use Phoenix.Socket

  channel "hologram", Hologram.Runtime.Channel

  @impl true
  def connect(_, socket, _) do
    {:ok, socket}
  end

  @impl true
  def id(_), do: nil
end
