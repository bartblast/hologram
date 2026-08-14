defmodule HologramFeatureTests.Patching.Page11 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/11"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :banner?, false)
  end

  # Three panels, each a conditional followed by a stateful sibling, all toggled by one button so
  # that a single patch changes three separate regions at once. The inputs are uncontrolled, so
  # what gets typed lives only in the DOM and cannot be repainted by a re-render.
  #
  # Panel A is the failing shape: the conditional's element and the keeper are both divs, and the
  # client pairs keyless siblings by tag and position, so showing the banner pairs the keeper with
  # the banner and rebuilds the input. Panel B differs only in the banner's tag, which is enough
  # for the pairing to miss and the keeper to survive - nothing in the template says A and B should
  # behave differently, the tag names decide it. Panel C wraps the conditional in an
  # always-rendered element, the workaround that held the slot before elements carried keys.
  #
  # B and C are here to pin down that keys leave the already-working shapes working.
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

        <div class="panel" id="panel_a">
          {%if @banner?}
            <div class="banner">banner a</div>
          {/if}
          <div class="keeper">
            <input type="text" id="input_a" />
          </div>
        </div>

        <div class="panel" id="panel_b">
          {%if @banner?}
            <p class="banner">banner b</p>
          {/if}
          <div class="keeper">
            <input type="text" id="input_b" />
          </div>
        </div>

        <div class="panel" id="panel_c">
          <div style="display: contents">
            {%if @banner?}
              <div class="banner">banner c</div>
            {/if}
          </div>
          <div class="keeper">
            <input type="text" id="input_c" />
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
