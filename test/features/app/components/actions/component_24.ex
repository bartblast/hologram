defmodule HologramFeatureTests.Components.Actions.Component24 do
  use Hologram.Component

  prop :value, :string

  # An in-place editor: it shows its own draft while editing and the owner's value otherwise. A
  # commit both leaves editing and forwards the draft to the owner in a next action, so for the
  # length of that chain the value shown has two sources - a frame painted in between would show
  # the owner's old value.
  def init(_props, component, _server) do
    put_state(component, draft: nil, editing?: false)
  end

  def template do
    ~HOLO"""
    <p>
      Component 24 shown:
      <strong id="component_24_shown">{%if @editing?}{@draft}{%else}{@value}{/if}</strong>
    </p>
    <p>
      <button $click="component_24_commit">Commit Component 24 Draft</button>
      <button $click="component_24_edit">Edit Component 24 Draft</button>
    </p>
    """
  end

  def action(:component_24_commit, _params, component) do
    component
    |> put_state(:editing?, false)
    |> put_action(
      name: :component_23_commit,
      target: "component_23",
      params: %{value: component.state.draft}
    )
  end

  def action(:component_24_edit, _params, component) do
    put_state(component, draft: "NEW", editing?: true)
  end
end
