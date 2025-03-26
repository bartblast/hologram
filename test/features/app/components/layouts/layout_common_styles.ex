defmodule HologramFeatureTests.Components.CommonLayoutStyles do
  use Hologram.Component

  def template do
    ~HOLO"""
    <style>
      {%raw}
        body {
          padding: 25px;
        }
          
        button {
          margin-bottom: 10px;
          margin-right: 5px;
        }
      {/raw}
    </style>
    """
  end
end
