defmodule HologramFeatureTests.Components.DefaultLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~H"""
    <html>
      <head>
        <Runtime />
      </head>
      <body style="padding: 25px">
        <slot />
      </body>
    </html>
    """
  end
end
