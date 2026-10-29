defmodule Hologram.UI.Runtime do
  use Hologram.Component
  alias Hologram.Router.Helpers, as: RouterHelpers

  prop :csp_nonce, :string, default: nil, from_context: {Hologram.Runtime, :csp_nonce}
  prop :initial_page?, :boolean, from_context: {Hologram.Runtime, :initial_page?}
  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}
  prop :page_module, :module, from_context: {Hologram.Runtime, :page_module}
  prop :page_mounted?, :boolean, from_context: {Hologram.Runtime, :page_mounted?}

  @impl Component
  def template do
    ~HOLO"""
    {%if @initial_page? && !@page_mounted?}
      <script>
        globalThis.Hologram ??= \{\};
        globalThis.Hologram._pendingJsInteropActions = [];
        {%if @csp_nonce}globalThis.Hologram.cspNonce = "{@csp_nonce}";{/if}

        globalThis.Hologram.dispatchAction = function(actionName, target, params) \{
          globalThis.Hologram._pendingJsInteropActions.push([actionName, target, params]);
        \}
      </script>
      <hologram-fill name="boot_data" />
      <script async src={asset_path("hologram/runtime.js")}></script>
      <hologram-fill name="chunk_script_tags" />
    {/if}

    {%if !@page_mounted?}
      <script async src={RouterHelpers.page_bundle_path(@page_module, @page_digest)}></script>
    {/if}
    """
  end
end
