defmodule HologramFeatureTests.MountDataPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/mount-data"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:bytes, <<240, 145, 163>>)
    |> put_state(:snippet, "<div><script>alert(1)</script></div>")
    |> put_state(:status, "not clicked")
  end

  def template do
    ~HOLO"""
    <p>
      Bytes: <strong id="bytes">{inspect(@bytes)}</strong>
    </p>
    <p>
      Snippet: <strong id="snippet">{@snippet}</strong>
    </p>
    <p>
      <button id="button" $click="click"> Click </button>
    </p>
    <p>
      Status: <strong id="status">{@status}</strong>
    </p>
    """
  end

  def action(:click, _params, component) do
    put_state(component, :status, "clicked")
  end
end
