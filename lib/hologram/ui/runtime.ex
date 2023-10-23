defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}
  prop :page_mounted?, :boolean, from_context: {Hologram.Runtime, :page_mounted?}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if !@page_mounted?}
        {%raw}
          window.__hologramPageMountData__ = (deps) => {
            const Type = deps.Type;
            
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
