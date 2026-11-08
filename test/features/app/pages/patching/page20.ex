defmodule HologramFeatureTests.Patching.Page20 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/20"

  layout HologramFeatureTests.Components.EmptyLayout

  state :claims, :list
  state :items, :list

  def init(_params, component, _server) do
    put_state(component,
      claims: [],
      items: [
        %{id: 1, name: "Alpha"},
        %{id: 2, name: "Bravo"},
        %{id: 3, name: "Charlie"}
      ]
    )
  end

  # A list whose items carry an :id, so the loop keys each row by it with no $key in the template.
  # Every row holds state only its DOM node knows: a typed value in an unbound input, focus, and a
  # spent once binding. Each row's id attribute follows its item, so a node reused for another item
  # would answer to that item's id while still holding the old item's state.
  #
  # The script in each row counts how many row nodes were ever created and stamps the row it sits
  # in: a script runs when its element is inserted, so a row rebuilt rather than kept runs it again
  # and is not the stamped node any more.
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
          <button id="remove_first" $click="remove_first">Remove first</button>
          <button id="reverse" $click="reverse">Reverse</button>
          <button id="insert_in_middle" $click="insert_in_middle">Insert in the middle</button>
        </p>

        <ul id="rows">
          {%for item <- @items}
            <li id="row_{item.id}">
              <script>
                window.__rowRuns = (window.__rowRuns || 0) + 1;
                document.currentScript.parentNode.__stamped = true;
              </script>
              <input id="input_{item.id}" />
              <button id="claim_{item.id}" $click.once={:claim, name: item.name}>Claim {item.name}</button>
            </li>
          {/for}
        </ul>

        <div id="result">{Enum.map_join(@items, ", ", & &1.name)}</div>
        <div id="claims">{@claims |> Enum.reverse() |> Enum.join(", ")}</div>
      </body>
    </html>
    """
  end

  def action(:claim, %{name: name}, component) do
    put_state(component, :claims, [name | component.state.claims])
  end

  def action(:insert_in_middle, _params, component) do
    [first | rest] = component.state.items

    put_state(component, :items, [first, %{id: 4, name: "Delta"} | rest])
  end

  def action(:remove_first, _params, component) do
    put_state(component, :items, tl(component.state.items))
  end

  def action(:reverse, _params, component) do
    put_state(component, :items, Enum.reverse(component.state.items))
  end
end
