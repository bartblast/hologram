defmodule Hologram.UI.Runtime do
  use Hologram.Component

  alias Hologram.Assets.ManifestCache, as: AssetManifestCache
  alias Hologram.Router.Helpers, as: RouterHelpers

  prop :initial_page?, :boolean, from_context: {Hologram.Runtime, :initial_page?}
  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}
  prop :page_mounted?, :boolean, from_context: {Hologram.Runtime, :page_mounted?}

  @impl Component
  def template do
    ~HOLO"""
    {%if @initial_page? && !@page_mounted?}
      <script>
        globalThis.hologram ??= \{\};
        {AssetManifestCache.get_manifest_js()}
      </script>
    {/if}

    {%if !@page_mounted?}
      <script>
        {%raw}
          globalThis.hologram.pageMountData = (deps) => {
            const Type = deps.Type;
            
            return {
              componentRegistry: $COMPONENT_REGISTRY_JS_PLACEHOLDER,
              pageModule: $PAGE_MODULE_JS_PLACEHOLDER,
              pageParams: $PAGE_PARAMS_JS_PLACEHOLDER
            };
          };
        {/raw}
      </script>
    {/if}

    {%if @initial_page? && !@page_mounted?}
      <script async src={asset_path("hologram/runtime.js")}></script>
    {/if}

    {%if !@page_mounted?}
      <script async src={RouterHelpers.page_bundle_path(@page_digest)}></script>
    {/if}
    """
  end
end
