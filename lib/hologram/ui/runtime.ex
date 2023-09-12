defmodule Hologram.UI.Runtime do
  use Hologram.Component

  prop :initial_client_data, :string, from_context: {Hologram.Runtime, :initial_client_data}

  @impl Component
  def template do
    ~H"""
    <script>
      window.__hologram_runtime_initial_client_data__ = "{@initial_client_data}";
    </script>
    """
  end
end
