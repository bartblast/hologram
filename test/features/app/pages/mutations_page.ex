defmodule HologramFeatureTests.MutationsPage do
  use Hologram.Page
  use Hologram.DB

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  alias HologramFeatureTests.Components.Mutations.Items
  alias HologramFeatureTests.Components.Mutations.Jobs
  alias HologramFeatureTests.Components.Mutations.Notes
  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Item
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Jobs.RestockItem

  route "/mutations"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :create_restock_job}> Create restock job </button>
      <button $click={command: :log_in}> Log in </button>
      <button $click="put_author"> Put author </button>
      <button $click="read_bound_row_field"> Read bound row field </button>
      <button $click="read_forgotten_pin"> Read forgotten pin </button>
      <button $click="read_mistyped_filter"> Read mistyped filter </button>
      <button $click="read_query_by_id"> Read query by id </button>
      <button $click={command: :restock_item}> Restock item </button>
    </p>
    <Notes cid="notes" />
    <Items cid="items" />
    <Jobs cid="jobs" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # A relationship goes where only an attribute does, so the stage refuses the call in the browser.
  def action(:put_author, _params, component) do
    [body: "unsaved"]
    |> Note.new()
    |> put_attribute(:author, nil)

    component
  end

  # Inside the quantifier a bare name is the channel's, and only the message has a position.
  def action(:read_bound_row_field, _params, component) do
    Channel
    |> filter(any(message <- messages, position > 1))
    |> DB.read()

    component
  end

  # The bare search reads an attribute the note doesn't declare - the variable missing its pin. The
  # pinned read beside it keeps the variable used.
  def action(:read_forgotten_pin, _params, component) do
    search = "hi"

    Note
    |> filter(body == search and body != ^search)
    |> DB.read()

    component
  end

  # A string is compared with a boolean attribute, so the filter refuses it in the browser - before
  # the read answers the rows the string unboxes to. The value goes through wrap_term/1, so neither
  # the type checker nor Dialyzer flags it.
  def action(:read_mistyped_filter, _params, component) do
    value = wrap_term("yes")

    Note
    |> filter(pinned: ^value)
    |> DB.read()

    component
  end

  # A query goes where the entity type does, so the by-id read refuses it in the browser - naming
  # the query it was handed.
  def action(:read_query_by_id, _params, component) do
    Note
    |> take(10)
    |> wrap_term()
    |> DB.read("018f0000-0000-7000-8000-000000000001")

    component
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:create_restock_job, _params, server) do
    item =
      Item
      |> filter(name: "widget")
      |> one()
      |> DB.read()

    Job.create!(RestockItem, amount: 1, item_id: item.id)

    put_action(server, :show_result, result: "created_restock_job")
  end

  def command(:log_in, _params, server) do
    user =
      %{email: "session@example.com"}
      |> User.new()
      |> trust()
      |> DB.create!()

    put_action(%{server | user_id: user.id}, :show_result, result: "logged_in")
  end

  def command(:restock_item, _params, server) do
    Item
    |> filter(name: "widget")
    |> one()
    |> DB.read()
    |> increment(:stock, 1)
    |> DB.update!()

    put_action(server, :show_result, result: "restocked_item")
  end
end
