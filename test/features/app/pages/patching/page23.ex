defmodule HologramFeatureTests.Patching.Page23 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/23"

  layout HologramFeatureTests.Components.EmptyLayout

  state :names, :list

  state :records, :list

  def init(_params, component, _server) do
    names = ["alpha", "bravo", "charlie"]

    put_state(component, names: names, records: to_records(names))
  end

  # Two lists whose loop items get no automatic key: the first loops over plain values and keys
  # its rows by an identifier, the second loops over the {record, index} pairs Enum.with_index/1
  # gives and keys its rows by the record. A plain value or a pair carries no :id, while a bare
  # record would be keyed by its :id automatically, which is why the second list loops over the
  # pairs. Each row holds a typed value only its DOM node knows, and its id attribute follows its
  # item.
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

        <ul id="identifier_rows">
          {%for name <- @names}
            <li id="identifier_row_{name}" $key={:name, name}>
              <input id="identifier_input_{name}" />
            </li>
          {/for}
        </ul>

        <ul id="record_rows">
          {%for {record, _index} <- Enum.with_index(@records)}
            <li id="record_row_{record.name}" $key={record}>
              <input id="record_input_{record.name}" />
            </li>
          {/for}
        </ul>

        <div id="result">{Enum.join(@names, ", ")}</div>
      </body>
    </html>
    """
  end

  def action(:remove_first, _params, component) do
    names = tl(component.state.names)

    put_state(component, names: names, records: to_records(names))
  end

  def action(:reverse, _params, component) do
    names = Enum.reverse(component.state.names)

    put_state(component, names: names, records: to_records(names))
  end

  defp to_records(names) do
    Enum.map(names, &%{id: &1, name: &1})
  end
end
