defmodule HologramFeatureTests.Components.Navigation.LeftListenersBox do
  use Hologram.Component

  prop :kind, :string

  def init(_props, component, _server) do
    put_state(component, :resize, 0)
  end

  # Each kind is a binding the listener registry holds, rather than the element it is written on,
  # which makes it the sort of listener that outlives the markup of the page that rendered it.
  # One kind is rendered at a time: a resize observer reports every navigation, so with all of
  # them on the page no feature could say which listener it was about.
  def template do
    ~HOLO"""
    {%if @kind == "resize"}
      <div $resize="record_resize" id="resize_box" style="height: 100px">Content</div>
    {/if}
    """
  end

  def action(:record_resize, _params, component) do
    put_state(component, :resize, component.state.resize + 1)
  end
end
