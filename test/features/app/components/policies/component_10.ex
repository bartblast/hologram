defmodule HologramFeatureTests.Components.Policies.Component10 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Milestone
  alias HologramFeatureTests.Entities.Project
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :milestones, [Milestone], &milestones_query/0
  derived :projects, [Project], &projects_query/0

  # Checked while rendering, so each check ships to the browser and is answered again on every
  # render the stream schedules - from the member rows it holds for the update rule's any, and for
  # the delete rule's none from the milestones it holds, or the server's verdict when it holds none.
  def template do
    ~HOLO"""
    <p>
      Milestones: <strong id="milestones"><code>{Enum.map_join(@milestones, ",", & &1.title)}</code></strong>
    </p>
    <p>
      Editable: <strong id="editable_milestones"><code>{Enum.map_join(allowed(@current_user, :update, @milestones), ",", & &1.title)}</code></strong>
    </p>
    <p>
      Deletable: <strong id="deletable_projects"><code>{Enum.map_join(allowed(@current_user, :delete, @projects), ",", & &1.name)}</code></strong>
    </p>
    """
  end

  defp allowed(user, operation, entities) do
    Enum.filter(entities, &can?(user, operation, &1))
  end

  defp milestones_query do
    sort(Milestone, title)
  end

  defp projects_query do
    sort(Project, name)
  end
end
