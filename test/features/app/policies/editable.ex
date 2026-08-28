defmodule HologramFeatureTests.Policies.Editable do
  use Hologram.Policy

  role :editor
  role :owner, extends: :editor

  allow :read, to: [:editor, :owner]
  allow :manage_roles, to: :owner
end
