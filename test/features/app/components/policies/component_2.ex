defmodule HologramFeatureTests.Components.Policies.Component2 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}
  prop :documents, [Document], from_query: &documents_query/0

  # Checked while RENDERING, so the check ships to the client and re-answers itself on every
  # render the stream schedules - which is what makes a grant arriving change what is on screen.
  # No init/3: both props are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Managed: <strong id="managed_documents"><code>{Enum.map_join(managed(@current_user, @documents), ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp documents_query do
    order_by(Document, :title)
  end

  defp managed(user, documents) do
    Enum.filter(documents, &can?(user, :manage_roles, &1))
  end
end
