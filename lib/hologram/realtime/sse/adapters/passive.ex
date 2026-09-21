defmodule Hologram.Realtime.SSE.Adapters.Passive do
  @moduledoc false

  # For servers that end the stream's process themselves when the client goes away, such as
  # Cowboy, whose connection process shuts the request process down, and for any server
  # Hologram knows nothing about. There is nothing to arm and nothing to learn from the
  # mailbox.

  @behaviour Hologram.Realtime.SSE.Adapter

  @impl Hologram.Realtime.SSE.Adapter
  def handle_message(_message), do: :ignore

  @impl Hologram.Realtime.SSE.Adapter
  def watch(_conn), do: :ok
end
