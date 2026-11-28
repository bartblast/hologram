defmodule HologramFeatureTests.UpdateSyntaxPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.UpdateSyntaxStructFixture

  route "/update-syntax"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button id="missing key" $click="missing key"> missing key </button>
      <button id="struct update" $click="struct update"> struct update </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:"missing key", _params, component) do
    # The map is wrapped so the missing key is found at runtime - the type checker
    # warns about a literal map that lacks the updated key.
    map = wrap_term(%{a: 1})

    put_state(component, :result, %{map | x: 2})
  end

  def action(:"struct update", _params, component) do
    struct = %UpdateSyntaxStructFixture{limit: 1, other: 99}

    put_state(component, :result, %UpdateSyntaxStructFixture{struct | limit: 3})
  end
end
