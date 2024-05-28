defmodule Hologram.UI.Link do
  use Hologram.Component
  alias Hologram.RuntimeSettings

  prop :to, [:module, :string, :tuple]

  @impl Component
  def template do
    ~H"""
    <a 
      href={page_path(@to)}
      $pointerdown={%Action{name: RuntimeSettings.prefetch_page_action_name(), params: %{to: @to}}}
      $click={%Action{name: RuntimeSettings.navigate_to_prefetched_page_action_name(), params: %{to: @to}}}
    ><slot /></a>
    """
  end
end
