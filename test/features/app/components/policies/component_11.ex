defmodule HologramFeatureTests.Components.Policies.Component11 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Inspection
  alias HologramFeatureTests.Entities.Report
  alias HologramFeatureTests.Entities.ReportNote
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :inspections, [Inspection], &inspections_query/0
  derived :notes, [ReportNote], &notes_query/0
  derived :reports, [Report], &reports_query/0

  # Checked while rendering, so each check ships to the browser and is answered again on every
  # render the stream schedules. The read rules read a server-only attribute the browser never
  # holds, and the note's update rule asks the report's read rule, so the browser answers each from
  # the server's verdict on the report or inspection.
  def template do
    ~HOLO"""
    <p>
      Readable reports: <strong id="readable_reports"><code>{Enum.map_join(allowed(@current_user, :read, @reports), ",", & &1.title)}</code></strong>
    </p>
    <p>
      Editable notes: <strong id="editable_notes"><code>{Enum.map_join(allowed(@current_user, :update, @notes), ",", & &1.body)}</code></strong>
    </p>
    <p>
      Readable inspections: <strong id="readable_inspections"><code>{Enum.map_join(allowed(@current_user, :read, @inspections), ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp allowed(user, operation, entities) do
    Enum.filter(entities, &can?(user, operation, &1))
  end

  defp inspections_query do
    sort(Inspection, title)
  end

  defp notes_query do
    sort(ReportNote, body)
  end

  defp reports_query do
    sort(Report, title)
  end
end
