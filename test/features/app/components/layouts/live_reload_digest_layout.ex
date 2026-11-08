defmodule HologramFeatureTests.Components.LiveReloadDigestLayout do
  use Hologram.Component

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  # Links, through asset_path/1, a stylesheet the live reload tests write next to a digested copy of
  # it, to see which of the two the page links and swaps to.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
        <link rel="stylesheet" href={asset_path("assets/live_reload_digest.css")} />
      </head>
      <body>
        <slot />
      </body>
    </html>
    """
  end
end
