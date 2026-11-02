# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module52 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26

  prop :body, :string
  prop :entities, [Entity26], from_query: &entities_query/1

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query(body) do
    filter(Entity26, any(message <- messages, message.body == ^body))
  end
end
