defmodule HologramFeatureTests.Policies.Editable do
  use Hologram.Policy

  role :editor
  role :owner, extends: :editor

  allow :read, to: [:editor, :owner]
  allow :grant_role, to: [:editor, :owner]
  allow :revoke_role, to: [:editor, :owner]
end
