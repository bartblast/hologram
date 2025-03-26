defmodule HologramFeatureTests.Components.LayoutWithProps do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  prop :a, :string
  prop :b, :integer

  def init(props, component, _server) do
    put_state(component, :result, props)
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          Layout props: <strong id="layout_result"><code>{inspect(@result)}</code></strong>
        </p>  
      </body>
    </html>
    """
  end
end
