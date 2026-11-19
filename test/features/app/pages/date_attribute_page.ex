defmodule HologramFeatureTests.DateAttributePage do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.DateAttribute.Days
  alias HologramFeatureTests.Components.DateAttribute.Events
  alias HologramFeatureTests.Entities.Event

  route "/date-attribute"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string
  state :since, DateTime

  def init(_params, component, _server) do
    put_state(component, result: nil, since: warsaw_midnight())
  end

  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :add_march_event}> Add an event in March </button>
      <button $click={action: :add_warsaw_event}> Add an event at midnight in Warsaw </button>
      <button $click={action: :add_era_days}> Add four days across the eras </button>
      <button $click={action: :add_last_day}> Add the last day of 9999 </button>
    </p>
    <Events cid="events" since={@since} />
    <Days cid="days" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:add_era_days, _params, component) do
    # Written out of day order, so the list can only come out in day order if the ordering put it
    # there. A year past 9999 has no sigil, so it is a struct literal.
    days = [
      ~D[-0002-01-01],
      %Date{year: 10_000, month: 1, day: 1, calendar: Calendar.ISO},
      ~D[-0001-01-01],
      ~D[9999-12-31]
    ]

    for {day, index} <- Enum.with_index(days) do
      {:ok, _event} =
        %{held_on: day, name: "day_#{index}"}
        |> Event.new()
        |> DB.create()
    end

    put_state(component, :result, "created_days")
  end

  def action(:add_last_day, _params, component) do
    {:ok, _event} =
      %{held_on: ~D[9999-12-31], name: "last_day"}
      |> Event.new()
      |> DB.create()

    put_state(component, :result, "created_last_day")
  end

  def action(:add_march_event, _params, component) do
    {:ok, _event} =
      %{name: "march", starts_at: ~U[2026-03-02 00:00:00Z]}
      |> Event.new()
      |> DB.create()

    put_state(component, :result, "created_march")
  end

  def action(:add_warsaw_event, _params, component) do
    {:ok, _event} =
      %{name: "warsaw", starts_at: warsaw_midnight()}
      |> Event.new()
      |> DB.create()

    put_state(component, :result, "created_warsaw")
  end

  # The first of March at midnight in Warsaw, an hour ahead of UTC - built by hand, so no time zone
  # database is needed on either tier. It stands for 2026-02-28 23:00:00 UTC.
  defp warsaw_midnight do
    %DateTime{
      year: 2026,
      month: 3,
      day: 1,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      std_offset: 0,
      time_zone: "Europe/Warsaw",
      utc_offset: 3600,
      zone_abbr: "CET",
      calendar: Calendar.ISO
    }
  end
end
