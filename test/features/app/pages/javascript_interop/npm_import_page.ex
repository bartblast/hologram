defmodule HologramFeatureTests.JavaScriptInterop.NpmImportPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  js_import from: "decimal.js", as: :Decimal

  route "/js-interop/npm-import"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="call_npm_method"> Call npm method </button>
    </p>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:call_npm_method, _params, component) do
    result =
      :Decimal
      |> JS.new([100])
      |> JS.call(:plus, [23])
      |> JS.call(:toNumber, [])

    put_state(component, :result, {result, is_integer(result)})
  end
end
