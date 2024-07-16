defmodule HologramFeatureTests.Components.CommandsLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
      </head>
      <body style="padding: 25px">
        <p>
          <button id="layout_command_1" $click={%Command{name: :layout_command_1, params: %{a: 1, b: 2}}}> layout_command_1 </button>
          <button id="page_command_1" $click={%Command{name: :page_command_1, params: %{a: 1, b: 2}, target: "page"}}> page_command_1 </button>
          <button id="component_2_command_1" $click={%Command{name: :component_2_command_1, params: %{a: 1, b: 2}, target: "component_2"}}> component_2_command_1 </button>
        </p>
        <p>
          Layout result: <strong id="layout_result"><code>{inspect(@result)}</code></strong>
        </p>
        <slot />
      </body>
    </html>
    """
  end

  def action(:layout_action_1, params, component) do
    put_state(component, :result, {"layout_command_1", params})
  end

  def action(:layout_action_2, params, component) do
    put_state(component, :result, {"layout_command_2", params})
  end

  def action(:layout_action_3, params, component) do
    put_state(component, :result, {"layout_command_3", params})
  end

  def command(:layout_command_1, params, server) do
    put_action(server, :layout_action_1, params)
  end

  def command(:layout_command_2, params, server) do
    put_action(server, :layout_action_2, params)
  end

  def command(:layout_command_3, params, server) do
    put_action(server, :layout_action_3, params)
  end
end
