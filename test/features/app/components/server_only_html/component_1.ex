defmodule HologramFeatureTests.Components.ServerOnlyHtml.Component1 do
  use Hologram.Component

  alias HologramFeatureTests.Entities.Document

  prop :document, Document

  def template do
    ~HOLO"""
    <p>
      Component API token: <strong id="component_api_token"><code>{%if server_only?(@document.api_token)}server_only{%else}{@document.api_token}{/if}</code></strong>
    </p>
    """
  end
end
