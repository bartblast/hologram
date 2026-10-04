defmodule HologramFeatureTests.Navigation.LeftListenersPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Components.Navigation.LeftListenersBox
  alias HologramFeatureTests.Navigation.LeftListenersDestinationPage

  route "/navigation/left-listeners/:kind"

  param :kind, :string

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <LeftListenersBox cid="left_listeners_box" kind={@kind} />
    <Link to={LeftListenersDestinationPage, kind: @kind}>Destination link</Link>
    """
  end
end
