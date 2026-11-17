defmodule HologramFeatureTests.Components.SessionUser.Component1 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.User

  prop :current_user, User, from_context: {Hologram, :user}

  def template do
    ~HOLO"""
    <p>
      <button $click="rename_locally"> Rename locally </button>
    </p>
    <p>
      Session user: <strong id="session_user"><code>{session_user_email(@current_user)}</code></strong>
    </p>
    """
  end

  # Runs in the BROWSER, against the client's own database, so the context answers with the new
  # email before the write reaches the server.
  def action(:rename_locally, _params, component) do
    component.props.current_user
    |> put_attribute(email: "renamed_locally@example.com")
    |> DB.update!()

    component
  end

  defp session_user_email(nil), do: "anonymous"

  defp session_user_email(user), do: user.email
end
