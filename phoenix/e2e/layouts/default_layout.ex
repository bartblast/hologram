defmodule Hologram.E2E.DefaultLayout do
  use Hologram.Layout

  def template do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram Demo</title>
        <Hologram.UI.Runtime />
      </head>
      <body>
        default layout:
        <slot />
      </body>
    </html>
    """
  end
end
