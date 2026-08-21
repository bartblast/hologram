# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module35 do
  use Hologram.Component

  prop :user, :map, required: true, from_context: :current_user

  def template do
    ~HOLO"Module35 template"
  end
end
