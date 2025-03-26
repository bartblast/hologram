defmodule Hologram.UI.Link do
  use Hologram.Component

  prop :class, :string, default: nil
  prop :rel, :string, default: nil
  prop :style, :string, default: nil
  prop :to, [:module, :string, :tuple]

  @impl Component
  def template do
    ~HOLO"""
    <a 
      href={page_path(@to)}
      class={@class}
      rel={@rel}
      style={@style}
      $pointerdown={:__prefetch_page__, to: @to}
      $click={:__load_prefetched_page__, to: @to}
    ><slot /></a>
    """
  end
end
