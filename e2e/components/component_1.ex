defmodule Hologram.E2E.Component1 do
  use Hologram.Component

  def template do
    ~H"""
    in component 1 template header
    <slot />
    in component 1 template footer
    """
  end
end
