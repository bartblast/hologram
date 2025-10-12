defmodule Hologram.LiveReload.Broadcaster do
  @moduledoc false

  @doc """
  Broadcasts a compilation error to all connected clients.

  Uses Phoenix.PubSub to notify clients about compilation errors
  so they can display them in the browser console or UI.
  """
  @spec broadcast_compilation_error(String.t()) :: :ok | {:error, term}
  def broadcast_compilation_error(output) do
    Phoenix.PubSub.broadcast(
      Hologram.PubSub,
      "hologram_live_reload",
      {:compilation_error, output}
    )
  end

  @doc """
  Broadcasts a reload notification to all connected clients.

  Uses Phoenix.PubSub to notify clients that they should reload the page
  after successful compilation.
  """
  @spec broadcast_reload :: :ok | {:error, term}
  def broadcast_reload do
    Phoenix.PubSub.broadcast(Hologram.PubSub, "hologram_live_reload", :reload)
  end
end
