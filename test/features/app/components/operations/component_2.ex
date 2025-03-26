defmodule HologramFeatureTests.Components.Operations.Component2 do
  use Hologram.Component

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button id="layout_command_3" $click={command: :layout_command_3, target: "layout", params: %{a: 1, b: 2}}> layout_command_3 </button>
      <button id="page_command_3" $click={command: :page_command_3, target: "page", params: %{a: 1, b: 2}}> page_command_3 </button>
      <button id="component_2_command_3" $click={command: :component_2_command_3, params: %{a: 1, b: 2}}> component_2_command_3 </button>
    </p>        
    <p>
      Component 2 result: <strong id="component_2_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:component_2_action_1, params, component) do
    put_state(component, :result, {"component_2_command_1", params})
  end

  def action(:component_2_action_2, params, component) do
    put_state(component, :result, {"component_2_command_2", params})
  end

  def action(:component_2_action_3, params, component) do
    put_state(component, :result, {"component_2_command_3", params})
  end

  def command(:component_2_command_1, params, server) do
    put_action(server, :component_2_action_1, params)
  end

  def command(:component_2_command_2, params, server) do
    put_action(server, :component_2_action_2, params)
  end

  def command(:component_2_command_3, params, server) do
    put_action(server, :component_2_action_3, params)
  end
end
