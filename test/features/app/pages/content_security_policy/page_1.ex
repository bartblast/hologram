defmodule HologramFeatureTests.ContentSecurityPolicy.Page1 do
  use Hologram.Page
  use Hologram.JS

  alias Hologram.UI.Link
  alias HologramFeatureTests.ContentSecurityPolicy.Page3

  route "/content-security-policy/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="evaluate_code">Evaluate code</button>
    </p>
    <p>
      <Link to={Page3}>Page 3 link</Link>
    </p>
    <p>
      Result: <strong id="result">{@result}</strong>
    </p>
    """
  end

  def action(:evaluate_code, _params, component) do
    put_state(component, :result, "evaluated #{JS.exec("return 20 + 1")}")
  end
end
