defmodule Hologram.E2E.Component2 do
  use Hologram.Component

  def template do
    ~H"""
    in component 2 template header
    <slot />
    in component 2 template footer
    """
  end
end
