defmodule HologramFeatureTests.Patching.Page17 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/17"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :banner?, false)
  end

  # A conditional ahead of a sibling that holds state the DOM keeps on its own, toggled by one
  # button. Page 11 asks whether such a sibling survives; this one asks whether what it was holding
  # survives with it, which is the stronger question: a node can be moved rather than rebuilt and
  # lose its state anyway, and a test that only compares node identity would call that a pass.
  #
  # The banner and the container are both divs, which is the shape that pairs wrongly when siblings
  # are matched by tag and position. Keys are what stop it, so this is the shape where their
  # absence would show.
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
        <p>
          <button $click="toggle_banner">Toggle banner</button>
        </p>

        <div id="panel">
          {%if @banner?}
            <div class="banner">banner</div>
          {/if}
          <div id="feed" style="height: 40px; overflow: auto">
            <p style="height: 400px">tall enough to scroll</p>
          </div>
        </div>

        <div id="result">{@banner?}</div>
      </body>
    </html>
    """
  end

  def action(:toggle_banner, _params, component) do
    put_state(component, :banner?, !component.state.banner?)
  end
end
