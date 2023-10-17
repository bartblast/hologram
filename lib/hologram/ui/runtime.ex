defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :client_data_loaded?, :boolean, from_context: {Hologram.Runtime, :client_data_loaded?}
  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if !@client_data_loaded?}
        window.__hologramClientData__ = "...";
        window.__hologramPageParams__ = "...";
      {/if}
    </script>
    <script async src={asset_path("hologram/runtime.js")}></script>
    <script async src="/hologram/page-{@page_digest}.js"></script>
    """
  end
end
