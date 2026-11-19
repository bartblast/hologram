defmodule HologramFeatureTests.Components.Policies.Component2 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :documents, [Document], &documents_query/0

  # Checked while RENDERING, so the check ships to the client and re-answers itself on every
  # render the stream schedules - which is what makes a grant arriving change what is on screen.
  # The held documents are every document the derived query answers, unchecked - on a client render
  # that is every document the browser's database holds, which tells a row arriving apart from a
  # check moving on a row already there.
  # No init/3: the prop and the derived field are rendered as they resolve.
  def template do
    ~HOLO"""
    <p>
      Managed: <strong id="managed_documents"><code>{Enum.map_join(managed(@current_user, @documents), ",", & &1.title)}</code></strong>
    </p>
    <p>
      Held: <strong id="held_documents"><code>{Enum.map_join(@documents, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp documents_query do
    sort(Document, title)
  end

  defp managed(user, documents) do
    Enum.filter(documents, &can?(user, :grant_role, &1))
  end
end
