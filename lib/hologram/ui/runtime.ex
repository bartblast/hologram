defmodule Hologram.UI.Runtime do
  use Hologram.Component
  alias Hologram.Assets.ManifestCache, as: AssetManifestCache

  prop :initial_page?, :boolean, from_context: {Hologram.Runtime, :initial_page?}
  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}
  prop :page_mounted?, :boolean, from_context: {Hologram.Runtime, :page_mounted?}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if @initial_page?}
        {AssetManifestCache.get_manifest_js()}
      {/if}
      {%if !@page_mounted?}
        {%raw}
          window.__hologramPageMountData__ = (deps) => {
            const Type = deps.Type;
            
            return {
              componentRegistry: $COMPONENT_REGISTRY_JS_PLACEHOLDER,
              pageModule: $PAGE_MODULE_JS_PLACEHOLDER,
              pageParams: $PAGE_PARAMS_JS_PLACEHOLDER
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
