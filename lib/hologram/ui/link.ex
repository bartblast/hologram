defmodule Hologram.UI.Link do
  use Hologram.Component

  prop :class, :string, default: nil
  prop :to, [:module, :string, :tuple]

  @impl Component
  def template do
    ~H"""
    <a 
      href={page_path(@to)}
      class={@class}
      $pointerdown={%Action{name: :__prefetch_page__, params: %{to: @to}}}
      $click={%Action{name: :__load_prefetched_page__, params: %{to: @to}}}
    ><slot /></a>
    """
  end
end
