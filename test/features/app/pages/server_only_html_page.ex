defmodule HologramFeatureTests.ServerOnlyHtmlPage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.ServerOnlyHtml.Component1
  alias HologramFeatureTests.Entities.Document

  route "/server-only-html"

  layout HologramFeatureTests.Components.DefaultLayout

  state :document, Document

  # Prints the token itself when the row holds it, so a leak shows up as the token's text.
  derived :derived_api_token, :string, fn document ->
    if server_only?(document.api_token), do: "server_only", else: document.api_token
  end

  # init/3 gets the real row, so the state holds the token until something strips it.
  def init(_params, component, _server) do
    document =
      Document
      |> filter(title: "server_only_html")
      |> one()
      |> DB.read()

    put_state(component, :document, document)
  end

  def template do
    ~HOLO"""
    <p>
      Page API token: <strong id="page_api_token"><code>{%if server_only?(@document.api_token)}server_only{%else}{@document.api_token}{/if}</code></strong>
    </p>
    <Component1 document={@document} />
    <p>
      Derived API token: <strong id="derived_api_token"><code>{@derived_api_token}</code></strong>
    </p>
    """
  end
end
