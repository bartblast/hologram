defmodule HologramFeatureTests.Patching.Page12 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles
  alias HologramFeatureTests.Components.Patching.Component1

  route "/patching/12"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :first_branch?, true)
  end

  # Switching a branch is the harder case than switching a block on and off, because both branches
  # render content and the two differ in how many nodes they produce. Every branch element is a div,
  # the same tag as the keeper that follows it, so a mispaired sibling is rebuilt rather than
  # rescued. The inputs are uncontrolled, so what gets typed lives only in the DOM.
  #
  # Panel A changes node count between branches, one against two. Panel B holds a component in a
  # branch, whose node count isn't known where this page is compiled, so no size can be reserved
  # for it ahead of time.
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
          <button $click="switch_branch">Switch branch</button>
        </p>

        <div class="panel" id="panel_a">
          {%if @first_branch?}
            <div class="branch">single</div>
          {%else}
            <div class="branch">double 1</div>
            <div class="branch">double 2</div>
          {/if}
          <div class="keeper">
            <input type="text" id="input_a" />
          </div>
        </div>

        <div class="panel" id="panel_b">
          {%if @first_branch?}
            <Component1 />
          {%else}
            <div class="branch">plain</div>
          {/if}
          <div class="keeper">
            <input type="text" id="input_b" />
          </div>
        </div>

        <div id="result">{@first_branch?}</div>
      </body>
    </html>
    """
  end

  def action(:switch_branch, _params, component) do
    put_state(component, :first_branch?, !component.state.first_branch?)
  end
end
