defmodule HologramFeatureTests.AssetManifestPage do
  use Hologram.Page

  route "/asset-manifest"

  layout HologramFeatureTests.Components.DefaultLayout

  # The file behind this path is planted by test/test_helper.exs, so this page works under
  # mix test only - visiting it under mix phx.server raises until that file exists.
  def init(_params, component, _server) do
    component
    |> put_state(:static_path, ~S|hostile/quote"backslash\tag</script>.txt|)
    |> put_state(:status, "not clicked")
  end

  def template do
    ~HOLO"""
    <p>
      Path: <strong id="path">{asset_path(@static_path)}</strong>
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
