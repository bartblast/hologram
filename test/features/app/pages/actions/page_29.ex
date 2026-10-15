defmodule HologramFeatureTests.Actions.Page29 do
  use Hologram.Page
  use Hologram.JS

  js_import from: "./helpers.mjs", as: :helpers

  route "/actions/29"

  layout HologramFeatureTests.Components.DefaultLayout

  # The result of an action must show while the next action it put, with no delay, awaits: the
  # next action renders nothing until its promise resolves.
  def init(_params, component, _server) do
    put_state(component, :status, "idle")
  end

  def template do
    ~HOLO"""
    <h1>Page 29 title</h1>
    <p>
      Status: <strong id="status">{@status}</strong>
    </p>
    <p>
      <button $click="submit">Submit Page 29 Form</button>
    </p>
    """
  end

  def action(:submit, _params, component) do
    component
    |> put_state(:status, "loading")
    |> put_action(:work)
  end

  def action(:work, _params, component) do
    :helpers
    |> JS.call(:slowValue, [1_000])
    |> Task.await()

    put_state(component, :status, "done")
  end
end
