defmodule HologramFeatureTests.Components.Derived.Component1 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Ticket

  prop :excluded_title, :string

  state :copied_summary, :string
  state :priority, :atom

  # A value computed from the rows the query below answers with, recomputed whenever they change.
  derived :summary, :string, fn tickets ->
    Enum.map_join(tickets, "/", &String.upcase(&1.title))
  end

  # Reads a prop and a state entry, so the rows it answers with follow both.
  derived :tickets, [Ticket], fn excluded_title, priority ->
    Ticket
    |> filter(priority == ^priority and title != ^excluded_title)
    |> sort(title)
  end

  def init(_props, component, _server) do
    component
    |> put_state(:copied_summary, "none")
    |> put_state(:priority, :high)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="copy_summary">Copy summary</button>
      <button $click="show_low">Show low</button>
    </p>
    <p>
      Tickets: <strong id="tickets"><code>{Enum.map_join(@tickets, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Summary: <strong id="summary"><code>{@summary}</code></strong>
    </p>
    <p>
      Copied summary: <strong id="copied_summary"><code>{@copied_summary}</code></strong>
    </p>
    """
  end

  def action(:copy_summary, _params, component) do
    put_state(component, :copied_summary, component.derived.summary)
  end

  def action(:show_low, _params, component) do
    put_state(component, :priority, :low)
  end
end
