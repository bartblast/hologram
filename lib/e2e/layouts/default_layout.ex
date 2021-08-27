defmodule Hologram.E2E.DefaultLayout do
  use Hologram.Layout

  def template do
    ~H"""
    <body>
      default layout:
      <slot />
    </body>
    """
  end
end
