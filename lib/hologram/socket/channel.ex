defmodule Hologram.Socket.Channel do
  @moduledoc false

  use Phoenix.Channel

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Socket.Decoder

  @impl Phoenix.Channel
  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_in("page_bundle_path", payload, socket) do
    page_bundle_path =
      payload
      |> Decoder.decode()
      |> PageDigestRegistry.lookup()
      |> RouterHelpers.page_bundle_path()

    {:reply, {:ok, page_bundle_path}, socket}
  end
end
