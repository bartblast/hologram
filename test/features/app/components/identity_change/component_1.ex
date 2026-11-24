defmodule HologramFeatureTests.Components.IdentityChange.Component1 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Memo
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  derived :memos, [Memo], &memos_query/0

  def template do
    ~HOLO"""
    <p>
      <button $click="write_note"> Write note </button>
    </p>
    <p>
      Session user: <strong id="session_user"><code>{session_user_email(@current_user)}</code></strong>
    </p>
    <p>
      Memos: <strong id="memos"><code>{Enum.map_join(@memos, ",", & &1.body)}</code></strong>
    </p>
    """
  end

  # Runs in the BROWSER, as whoever the tab takes the session user to be, and the server checks
  # the author against who it takes the session user to be.
  def action(:write_note, _params, component) do
    %{author_id: component.props.current_user.id, body: "browser_note"}
    |> Note.new()
    |> DB.create!()

    component
  end

  defp memos_query do
    sort(Memo, body)
  end

  defp session_user_email(nil), do: "anonymous"

  defp session_user_email(user), do: user.email
end
