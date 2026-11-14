# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module35 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module1

  attribute :public, :boolean, default: false

  relationship :children, [Module1]

  role :viewer

  allow :read, when: public == true
  allow :read, to: :viewer
end
