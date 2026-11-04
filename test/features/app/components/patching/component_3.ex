defmodule HologramFeatureTests.Components.Patching.Component3 do
  use Hologram.Component

  prop :name, :string

  # A stateful row: the list keys it by its cid, with no $key written. The script counts and stamps
  # the row the way the page's own rows do.
  def template do
    ~HOLO"""
    <li id="stateful_row_{@name}">
      <script>
        window.__rowRuns = (window.__rowRuns || 0) + 1;
        document.currentScript.parentNode.__stamped = true;
      </script>
      <input id="stateful_input_{@name}" />
    </li>
    """
  end
end
