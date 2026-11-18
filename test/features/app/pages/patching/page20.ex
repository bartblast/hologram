defmodule HologramFeatureTests.Patching.Page20 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/20"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    component
    |> put_state(:color, "#FF0000")
    |> put_state(:count, 0)
  end

  # A color input reads its value back in lowercase, so state holding uppercase hex never equals
  # what the input shows. A value write moves an open picker, so a write on every render makes the
  # picker jump back while it's dragged. The input action upcases what the picker sends, the way an
  # app that stores colors in uppercase would.
  #
  # The script in the head wraps the value setter, before the runtime loads, to count the writes
  # to the color input. It writes nothing itself, and the native descriptor it saves lets the test
  # pick a color without going through the counter.
  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <script>
          {%raw}
            window.__nativeValue = Object.getOwnPropertyDescriptor(
              HTMLInputElement.prototype,
              "value",
            );

            window.__colorWrites = 0;

            Object.defineProperty(HTMLInputElement.prototype, "value", {
              ...window.__nativeValue,
              set(value) {
                if (this.id === "color_input") {
                  window.__colorWrites += 1;
                }

                window.__nativeValue.set.call(this, value);
              },
            });
          {/raw}
        </script>
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          <input type="color" id="color_input" value={@color} $input="color_input" />
        </p>

        <p>
          <button $click="rerender">Rerender</button>
        </p>

        <div id="state">{@color}</div>
        <div id="result">{@count}</div>
      </body>
    </html>
    """
  end

  def action(:color_input, params, component) do
    put_state(component, :color, String.upcase(params.event.value))
  end

  def action(:rerender, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
