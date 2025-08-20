defmodule HologramFeatureTests.Security.Page1 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Security.Page2

  route "/security/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <div>
      <h1>Security / Page 1</h1>
      <p>
        <button $click={:test_action_1, a: 100}>
          Test Action 1
        </button>      
        <button $click={command: :test_command, params: %{x: 200}}>
          Test Command
        </button>
      </p>
      <p>
        <Link to={Page2}>Navigate to Page 2</Link>
      </p>
      <p>
        Result: <strong id="result"><code>{inspect(@result)}</code></strong>
      </p>
    </div>
    """
  end

  def action(:render_command_result, params, component) do
    put_state(component, :result, params.y)
  end

  def action(:test_action_1, params, component) do
    put_state(component, :result, params.a + 1)
  end

  def command(:test_command, params, server) do
    put_action(server, :render_command_result, y: params.x + 1)
  end
end
