defmodule HologramFeatureTests.Patching.Page22 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles
  alias HologramFeatureTests.Components.Patching.Component2
  alias HologramFeatureTests.Components.Patching.Component3

  route "/patching/22"

  layout HologramFeatureTests.Components.EmptyLayout

  state :names, :list

  def init(_params, component, _server) do
    put_state(component, :names, ["alpha", "bravo", "charlie"])
  end

  # Three lists of plain values, which carry no :id, so nothing keys their items automatically:
  # the first keys its rows by a $key on the row element, the second by a $key on a stateless
  # component, and the third renders stateful components, which are keyed by their cid. Each row holds a
  # typed value only its DOM node knows, and its id attribute follows its item.
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
        </p>

        <ul id="element_rows">
          {%for name <- @names}
            <li id="element_row_{name}" $key={name}>
              <script>
                window.__rowRuns = (window.__rowRuns || 0) + 1;
                document.currentScript.parentNode.__stamped = true;
              </script>
              <input id="element_input_{name}" />
            </li>
          {/for}
        </ul>

        <ul id="component_rows">
          {%for name <- @names}
            <Component2 name={name} $key={name} />
          {/for}
        </ul>

        <ul id="stateful_rows">
          {%for name <- @names}
            <Component3 cid={"stateful_" <> name} name={name} />
          {/for}
        </ul>

        <div id="result">{Enum.join(@names, ", ")}</div>
      </body>
    </html>
    """
  end

  def action(:remove_first, _params, component) do
    put_state(component, :names, tl(component.state.names))
  end

  def action(:reverse, _params, component) do
    put_state(component, :names, Enum.reverse(component.state.names))
  end
end
