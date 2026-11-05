defmodule HologramFeatureTests.Components.Patching.Component2 do
  use Hologram.Component

  prop :name, :string

  # A stateless row: the list keys it through a $key on its tag, since its items are plain values.
  # The script counts and stamps the row the way the page's own rows do.
  def template do
    ~HOLO"""
    <li id="component_row_{@name}">
      <script>
        window.__rowRuns = (window.__rowRuns || 0) + 1;
        document.currentScript.parentNode.__stamped = true;
      </script>
      <input id="component_input_{@name}" />
    </li>
    """
  end
end
