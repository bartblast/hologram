defmodule HologramFeatureTests.Patching.Page14 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/14"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :hints?, true)
  end

  # Three conditionals on one flag, each ahead of a field, so a single click changes three separate
  # regions of the same children list at once. This is the shape position alone cannot rescue: the
  # diff loses its alignment at the first changed region, and without keys the fields between the
  # regions are rebuilt - the typed text goes with them, and can even reappear in the wrong field.
  # It takes each field carrying the key of its own place for them to hold still.
  #
  # Hiding is the direction that fails. Showing the hints again works either way, which is why the
  # test switches them off before checking anything. The fields are uncontrolled, so what gets
  # typed lives only in the DOM.
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
          <button $click="toggle_hints">Toggle hints</button>
        </p>

        <div id="form">
          {%if @hints?}
            <p class="hint">hint 1</p>
          {/if}
          <input type="text" id="field_1" />

          {%if @hints?}
            <p class="hint">hint 2</p>
          {/if}
          <input type="text" id="field_2" />

          {%if @hints?}
            <p class="hint">hint 3</p>
          {/if}
          <input type="text" id="field_3" />
        </div>

        <div id="result">{@hints?}</div>
      </body>
    </html>
    """
  end

  def action(:toggle_hints, _params, component) do
    put_state(component, :hints?, !component.state.hints?)
  end
end
