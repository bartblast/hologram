defmodule HologramFeatureTests.Components.ForeignNodesLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # The tags other tools' nodes are put next to (see HologramFeatureTestsWeb.Plugs.ForeignNodes).
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Foreign nodes</title>
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
