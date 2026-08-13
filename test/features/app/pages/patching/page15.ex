defmodule HologramFeatureTests.Patching.Page15 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/15"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :items, [
      %{tag: "h2", text: "Alpha", starred?: true},
      %{tag: "p", text: "Bravo", starred?: true},
      %{tag: "blockquote", text: "Charlie", starred?: true},
      %{tag: "pre", text: "Delta", starred?: true}
    ])
  end

  # A loop whose body holds a block at the top level, reordered without adding or removing
  # anything. The compiler gives that block one marker, so every iteration renders the same one,
  # and a children list cannot carry a repeated key - the diff indexes them and would reach for a
  # node it already consumed. Page 13 renders the same shape, but its diff realigns on its own and
  # never consults the keys; what makes this one consult them is the dynamic tag, which gives the
  # entries different tag names, so the diff's positional probes all fail on a reorder.
  #
  # Reordering also moves the blocks themselves, which is the other half of what this exercises:
  # a block occupies one position however much it renders, so taking a different position has to
  # carry the nodes it stands for with it.
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
          <button $click="sort">Sort</button>
        </p>

        <div id="feed">
          {%for item <- @items}
            {%if item.starred?}<em class="star">*</em>{/if}
            <{item.tag}>{item.text}</{item.tag}>
          {/for}
        </div>

        <div id="result">{Enum.map_join(@items, ", ", & &1.text)}</div>
      </body>
    </html>
    """
  end

  def action(:sort, _params, component) do
    [item_1, item_2, item_3, item_4] = component.state.items

    put_state(component, :items, [item_3, item_1, item_4, item_2])
  end
end
