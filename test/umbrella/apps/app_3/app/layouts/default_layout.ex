defmodule App3.DefaultLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <Runtime />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
