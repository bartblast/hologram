defmodule HologramFeatureTests.Patching.Page13 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/13"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, items: ["item 1"], badges?: true)
  end

  # A loop shifts whatever follows it whenever its item count changes, exactly as a conditional
  # does when it turns on. The items are divs, the same tag as the keeper that follows them, so a
  # mispaired keeper is rebuilt rather than rescued, and the inputs are uncontrolled so what gets
  # typed lives only in the DOM.
  #
  # Panel A changes the loop's length around a keeper that follows it.
  #
  # Panel B holds a conditional inside the loop body, switched for every item at once. The
  # conditional's element is one place in the template, so every iteration renders the same key,
  # and a children list cannot carry a repeated key - the diff indexes them and would reach for a
  # node it already consumed. Three items make the repeat wide enough to matter.
  #
  # Its loop body is written on one line deliberately. Whitespace between iterations gives the diff
  # text nodes to stay aligned on, and the failure stops reproducing - reformatting that line would
  # leave a test that passes whether or not repeated keys are handled.
  #
  # Only the keepers are checked for identity. Which DOM node a given item keeps across a reorder
  # is a separate question, answered by keys the template author writes rather than by the ones the
  # compiler assigns to places.
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
          <button $click="add_item">Add item</button>
          <button $click="remove_item">Remove item</button>
          <button $click="toggle_badges">Toggle badges</button>
        </p>

        <div class="panel" id="panel_a">
          {%for item <- @items}
            <div class="item">{item}</div>
          {/for}
          <div class="keeper">
            <input type="text" id="input_a" />
          </div>
        </div>

        <div class="panel" id="panel_b">
          {%for item <- @items}{%if @badges?}<div class="badge">{item}</div>{/if}{/for}
          <div class="keeper">
            <input type="text" id="input_b" />
          </div>
        </div>

        <div id="result">{Enum.join(@items, ", ")}</div>
      </body>
    </html>
    """
  end

  def action(:add_item, _params, component) do
    items = component.state.items

    put_state(component, :items, items ++ ["item #{length(items) + 1}"])
  end

  def action(:remove_item, _params, component) do
    put_state(component, :items, Enum.drop(component.state.items, -1))
  end

  def action(:toggle_badges, _params, component) do
    put_state(component, :badges?, !component.state.badges?)
  end
end
