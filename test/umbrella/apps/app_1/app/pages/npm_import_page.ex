defmodule App1.NpmImportPage do
  use Hologram.Page
  use Hologram.JS

  js_import from: "decimal.js", as: :Decimal

  route "/npm-import"

  layout App1.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>npm import page</h1>
    <p>
      <button $click="add_decimals">Add decimals</button>
    </p>
    <p>
      Result: <strong id="result">{@result}</strong>
    </p>
    """
  end

  def action(:add_decimals, _params, component) do
    result =
      :Decimal
      |> JS.new([100])
      |> JS.call(:plus, [23])
      |> JS.call(:toNumber, [])

    put_state(component, :result, result)
  end
end
