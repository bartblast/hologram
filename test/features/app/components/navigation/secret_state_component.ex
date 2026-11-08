defmodule HologramFeatureTests.Components.Navigation.SecretStateComponent do
  use Hologram.Component

  # The actions build their values from the label prop, so after a restore from storage, which
  # keeps no props, they show that the first render gave the props back before any action ran.
  prop :label, :string

  state :note, :string, default: ""
  state :password, :string, default: "", secret: true

  def template do
    ~HOLO"""
    <button $click="put_component_note">Put component note</button>
    <button $click="put_component_password">Put component password</button>
    <p>
      Component note: <strong id="component_note">[{@note}]</strong>
    </p>
    <p>
      Component password: <strong id="component_password">[{@password}]</strong>
    </p>
    """
  end

  def action(:put_component_note, _params, component) do
    put_state(component, :note, "#{component.props.label} note")
  end

  def action(:put_component_password, _params, component) do
    put_state(component, :password, "#{component.props.label} password")
  end
end
