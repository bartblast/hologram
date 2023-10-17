defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :client_data_loaded?, :boolean, from_context: {Hologram.Runtime, :client_data_loaded?}
  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if !@client_data_loaded?}
        {%raw}
          window.__hologramPageMountData__ = (typeClass) => {
            return {
              clientsData: $INJECT_CLIENTS_DATA,
              pageModule: $INJECT_PAGE_MODULE,
              pageParams: $INJECT_PAGE_PARAMS
            };
          };
        {/raw}
      {/if}
    </script>
    <script async src={asset_path("hologram/runtime.js")}></script>
    <script async src="/hologram/page-{@page_digest}.js"></script>
    """
  end
end
