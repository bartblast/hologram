defmodule Hologram.Socket.Channel do
  @moduledoc false

  use Phoenix.Channel

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Socket.Decoder
  alias Hologram.Template.Renderer

  @impl Phoenix.Channel
  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  @impl Phoenix.Channel
  def handle_in("page", payload, socket) do
    opts = [initial_page?: false]

    {html, _component_registry} =
      case Decoder.decode(payload) do
        {page_module, params} ->
          Renderer.render_page(page_module, params, opts)

        page_module ->
          Renderer.render_page(page_module, %{}, opts)
      end

    {:reply, {:ok, html}, socket}
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
