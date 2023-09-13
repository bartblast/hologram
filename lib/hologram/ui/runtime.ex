defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :initial_client_data_loaded?, :boolean,
    from_context: {Hologram.Runtime, :initial_client_data_loaded?}

  @impl Component
  def template do
    ~H"""
    <script>
      {%if !@initial_client_data_loaded?}
        window.__hologram_runtime_initial_client_data__ = "...";
      {/if}
    </script>
    """
  end
end
