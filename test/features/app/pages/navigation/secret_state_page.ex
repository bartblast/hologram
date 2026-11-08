defmodule HologramFeatureTests.Navigation.SecretStatePage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Components.Navigation.SecretStateComponent
  alias HologramFeatureTests.Navigation.Page2

  route "/navigation/secret-state"

  layout HologramFeatureTests.Components.DefaultLayout

  # The note is an ordinary entry next to the secret one, so a restore that brings the note back
  # shows that the page came from its snapshot.
  state :note, :string, default: ""
  state :password, :string, default: "", secret: true

  def template do
    ~HOLO"""
    <h1>Secret state page title</h1>
    <button $click="put_note">Put note</button>
    <button $click="put_password">Put password</button>
    <Link to={Page2}>Page 2 link</Link>
    <p>
      Note: <strong id="note">[{@note}]</strong>
    </p>
    <p>
      Password: <strong id="password">[{@password}]</strong>
    </p>
    <SecretStateComponent cid="widget" label="widget" />
    """
  end

  def action(:put_note, _params, component) do
    put_state(component, :note, "typed note")
  end

  def action(:put_password, _params, component) do
    put_state(component, :password, "typed password")
  end
end
