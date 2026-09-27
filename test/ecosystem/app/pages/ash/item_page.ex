# The scenario on this page verifies that a field taken out of an Ash record server code creates holds
# only that field: the record's money price ships none of its protocol implementations, and neither
# does the localization library behind them. Client-reachable code on this page (template, actions)
# must not reference the money type, otherwise the scenario silently stops testing what the server
# code hands to the client.
defmodule HologramEcosystemTests.Ash.ItemPage do
  use Hologram.Page

  alias HologramEcosystemTests.Ash.Item

  route "/ash/item"

  layout HologramEcosystemTests.Components.DefaultLayout

  def init(_params, component, _server) do
    item = Item.create!(%{price: Money.new(:EUR, 10), title: "title"})

    put_state(component, :title, item.title)
  end

  def template do
    ~HOLO"""
    <p>
      Title: <strong id="title">{@title}</strong>
    </p>
    """
  end
end
