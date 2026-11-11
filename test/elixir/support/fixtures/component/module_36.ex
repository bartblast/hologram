defmodule Hologram.Test.Fixtures.Component.Module36 do
  use Hologram.Component

  prop :first_name, :string
  prop :last_name, :string

  state :shout, :boolean, default: false

  # Declared before the field it reads, so it is listed after it.
  derived :greeting, :string, fn full_name, shout ->
    text = "Hi " <> full_name

    if shout, do: String.upcase(text), else: text
  end

  derived :full_name, :string, fn first_name, last_name -> first_name <> " " <> last_name end

  derived :motto, :string, &motto/0

  @impl Component
  def template do
    ~HOLO""
  end

  defp motto, do: "Hello"
end
