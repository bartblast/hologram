# The scenario on this page verifies that a money struct that does reach the browser brings its
# chunks with it: init/3 puts the price of an Ash record into the state, so the money type's chunks
# are named in the page's document, and a command sends another price, whose chunks are named in
# the command's reply. Client-reachable code on this page (template, actions) must not name the
# money type, so that its chunks are loaded through the state and the reply, never preloaded.
#
# The template prints the price's currency and amount rather than the price itself. Turning a
# money struct into text formats it for a locale, and the localization library reads its locale
# data through a process, which has no counterpart in the browser. The amount is a decimal, whose
# String.Chars implementation is plain code from one of its own chunks.
defmodule HologramEcosystemTests.Ash.PricedItemPage do
  use Hologram.Page

  alias HologramEcosystemTests.Ash.Item

  route "/ash/priced-item"

  layout HologramEcosystemTests.Components.DefaultLayout

  def init(_params, component, _server) do
    item = Item.create!(%{price: Money.new(:EUR, 10), title: "title"})

    put_state(component, :price, item.price)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="reprice"> Reprice </button>
    </p>
    <p>
      Price: <strong id="price">{@price.currency} {@price.amount}</strong>
    </p>
    """
  end

  def action(:put_price, params, component) do
    put_state(component, :price, params.price)
  end

  def action(:reprice, _params, component) do
    put_command(component, :reprice)
  end

  def command(:reprice, _params, server) do
    put_action(server, :put_price, price: Money.new(:EUR, 20))
  end
end
