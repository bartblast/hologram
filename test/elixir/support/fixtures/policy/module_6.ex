# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module6 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14

  attribute :shared, :boolean, default: false

  relationship :author, Module14, optional: true

  allow :read, when: author_id == user_id() or shared == true
end
