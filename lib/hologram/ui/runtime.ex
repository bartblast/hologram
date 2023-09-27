defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :initial_client_data_loaded?, :boolean,
    from_context: {Hologram.Runtime, :initial_client_data_loaded?}

  prop :page_digest, :string, from_context: {Hologram.Runtime, :page_digest}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if !@initial_client_data_loaded?}
        window.__hologramRuntimeBootstrapData__ = "...";
      {/if}
    </script>
    <script async src="/assets/hologram/page-{@page_digest}.js"></script>
    """
  end
end
