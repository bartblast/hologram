# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module2 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Role.Module1, as: Role1

  attribute :public, :boolean, default: false

  role :admin
  role :member

  allow :read, to: :member
  allow :archive, to: Role1
  allow :publish, public: true
  allow :update, to: :admin
  allow :read_roles, to: :member
end
