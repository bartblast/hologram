defmodule HologramFeatureTests.Components.Rendering.Component1 do
  use Hologram.Component

  prop :text, :string

  # The length is measured in init/3, which runs on the server only, so the number travels to the
  # client in the component registry rather than being recomputed there. That is what makes the
  # test meaningful: the client's own render repairs the text it prints, but it adopts this number
  # as the server worked it out, so a prop the server received escaped shows up here as a wrong
  # count that survives the boot patch.
  def init(props, component, _server) do
    put_state(component, :length_on_server, String.length(props.text))
  end

  def template do
    ~HOLO"""
    <div id="text">{@text}</div>
    <div id="length">{@length_on_server}</div>
    """
  end
end
