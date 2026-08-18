defmodule Hologram.UI.Runtime do
  use Hologram.Component
  alias Hologram.Router.Helpers, as: RouterHelpers

  prop :csrf_token, :string, from_context: {Hologram, :csrf_token}
  prop :initial_page?, :boolean, from_context: {Hologram, :initial_page?}
  prop :instance_id, :string, from_context: {Hologram, :instance_id}
  prop :page_digest, :string, from_context: {Hologram, :page_digest}
  prop :page_mounted?, :boolean, from_context: {Hologram, :page_mounted?}

  @impl Component
  def template do
    ~HOLO"""
    {%if @initial_page? && !@page_mounted?}
      <script>
        globalThis.Hologram ??= \{\};
        globalThis.Hologram._pendingJsInteropActions = [];
        globalThis.Hologram.assetManifest = $ASSET_MANIFEST_JS_PLACEHOLDER;
        globalThis.Hologram.csrfToken = "{@csrf_token}";
        globalThis.Hologram.instanceId = "{@instance_id}";

        globalThis.Hologram.dispatchAction = function(actionName, target, params) \{
          globalThis.Hologram._pendingJsInteropActions.push([actionName, target, params]);
        \}
      </script>
    {/if}

    {%if !@page_mounted?}
      <script>
        {%raw}
          globalThis.Hologram.pageMountData = (deps) => {
            const Type = deps.Type;
            
            return {
              actorUserId: $ACTOR_USER_ID_JS_PLACEHOLDER,
              componentRegistry: $COMPONENT_REGISTRY_JS_PLACEHOLDER,
              pageModule: $PAGE_MODULE_JS_PLACEHOLDER,
              pageParams: $PAGE_PARAMS_JS_PLACEHOLDER,
              selfEchoes: $SELF_ECHOES_JS_PLACEHOLDER,
              subReceiptAdds: $SUB_RECEIPT_ADDS_JS_PLACEHOLDER,
              subReceiptDrops: $SUB_RECEIPT_DROPS_JS_PLACEHOLDER,
              syncCounts: $SYNC_COUNTS_JS_PLACEHOLDER,
              syncSeed: $SYNC_SEED_JS_PLACEHOLDER
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
