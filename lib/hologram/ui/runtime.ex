defmodule Hologram.UI.Runtime do
  use Hologram.Component
  alias Hologram.Router.Helpers, as: RouterHelpers

  prop :csp_nonce, :string, default: nil, from_context: {Hologram, :csp_nonce}
  prop :initial_page?, :boolean, from_context: {Hologram, :initial_page?}
  prop :page_digest, :string, from_context: {Hologram, :page_digest}
  prop :page_module, :module, from_context: {Hologram, :page_module}
  prop :page_mounted?, :boolean, from_context: {Hologram, :page_mounted?}

  # The inline script's popstate listener covers the time before the runtime has loaded. A Back in
  # that time leaves this document under another entry's URL, so the runtime reloads instead of
  # booting. A jump to a #fragment fires popstate too, with a null state and the same path and query
  # string, and keeps the document. Only string states are compared, since those are Hologram's
  # entry ids, and an object state arrives as a new clone that never equals the one read here.
  # The document's own state is kept for the runtime, which reloads an entry that shares it without
  # restoring a snapshot, since the snapshot under a shared id can be another entry's.
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

        globalThis.Hologram._documentState = history.state;

        globalThis.Hologram._popstateShim = (function(state, url) \{
          return function(event) \{
            if (location.pathname + location.search !== url || (typeof event.state === "string" && event.state !== state)) \{
              globalThis.Hologram._missedPopstate = true;
            \}
          \};
        \})(history.state, location.pathname + location.search);

        addEventListener("popstate", globalThis.Hologram._popstateShim);
      </script>
      <hologram-fill name="boot_data" />
      <hologram-fill name="data_model_script_tag" />
      <script async src={asset_path("hologram/runtime.js")}></script>
      <hologram-fill name="chunk_script_tags" />
    {/if}

    {%if !@page_mounted?}
      <script async src={RouterHelpers.page_bundle_path(@page_module, @page_digest)}></script>
    {/if}
    """
  end
end
