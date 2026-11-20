defmodule HologramFeatureTests.Components.Policies.Component13 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Tool
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :tools, [Tool], &tools_query/0

  # Checked while rendering, so each check ships to the browser and is answered again on every
  # render the stream schedules. Each rule reads a workshop, a bench or a permit the user may not
  # read, so the browser answers it from the server's verdict on the tool.
  def template do
    ~HOLO"""
    <p>
      Tools: <strong id="tools"><code>{labels(@tools)}</code></strong>
    </p>
    <p>
      Readable tools: <strong id="readable_tools"><code>{labels(Enum.filter(@tools, &can?(@current_user, :read, &1)))}</code></strong>
    </p>
    <p>
      Updatable tools: <strong id="updatable_tools"><code>{labels(Enum.filter(@tools, &can?(@current_user, :update, &1)))}</code></strong>
    </p>
    <p>
      Deletable tools: <strong id="deletable_tools"><code>{labels(Enum.filter(@tools, &can?(@current_user, :delete, &1)))}</code></strong>
    </p>
    <p>
      Relabelable tools: <strong id="relabelable_tools"><code>{labels(Enum.filter(@tools, &can?(@current_user, {:update, :label}, &1)))}</code></strong>
    </p>
    <p>
      Movable tools: <strong id="movable_tools"><code>{labels(Enum.filter(@tools, &can?(@current_user, {:update, :bench}, &1)))}</code></strong>
    </p>
    """
  end

  defp labels(tools), do: Enum.map_join(tools, ",", & &1.label)

  defp tools_query do
    sort(Tool, label)
  end
end
