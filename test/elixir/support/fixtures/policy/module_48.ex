# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module48 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module49

  attribute :approved, :boolean, default: false

  relationship :tool, Module49, optional: true

  allow :read, to: {:owner, tool.workshop}
end
