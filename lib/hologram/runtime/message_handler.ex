defmodule Hologram.Runtime.MessageHandler do
  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Server
  alias Hologram.Template.Renderer

  def handle("command", payload) do
    %{module: module, name: name, params: params, target: target} = payload

    result = module.command(name, params, %Server{})

    # TODO: handle session & cookies
    next_action =
      case result do
        %Server{next_action: action = %Action{target: nil}} ->
          %{action | target: target}

        %Server{next_action: action} ->
          action

        _fallback ->
          nil
      end

    Encoder.encode_term(next_action)
  end

  def handle("page", payload) do
    opts = [initial_page?: false]

    {html, _component_registry} =
      case payload do
        {page_module, params} ->
          Renderer.render_page(page_module, params, opts)

        page_module ->
          Renderer.render_page(page_module, %{}, opts)
      end

    {:ok, html}
  end

  def handle("page_bundle_path", page_module) do
    page_bundle_path =
      page_module
      |> PageDigestRegistry.lookup()
      |> RouterHelpers.page_bundle_path()

    {:ok, page_bundle_path}
  end
end
