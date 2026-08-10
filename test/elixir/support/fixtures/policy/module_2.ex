# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module2 do
  use Hologram.Entity

  attribute :public, :boolean, default: false

  role :admin, scope: :global
  role :member

  allow :read, to: :member
  allow :publish, public: true
  allow :update, to: :admin
  allow :read_grants, to: :member
end
