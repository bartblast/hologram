defmodule HologramFeatureTests.Patching.Page21 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles
  alias HologramFeatureTests.Patching.Page20
  alias HologramFeatureTests.Patching.Page22

  route "/patching/21"

  layout HologramFeatureTests.Components.EmptyLayout

  # The page a navigation to the keyed lists starts from.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <Link to={Page20}>Keyed list link</Link>
        <Link to={Page22}>Explicitly keyed lists link</Link>
      </body>
    </html>
    """
  end
end
