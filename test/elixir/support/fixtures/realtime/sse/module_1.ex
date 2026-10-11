defmodule Hologram.Test.Fixtures.Realtime.SSE.Module1 do
  @behaviour Hologram.Realtime.SSE.Adapter

  @impl Hologram.Realtime.SSE.Adapter
  def handle_message(:goodbye), do: :closed

  def handle_message(_message), do: :ignore

  @impl Hologram.Realtime.SSE.Adapter
  def watch(_conn), do: :ok
end
