defmodule Hologram.E2E.DefaultLayout do
  use Hologram.Layout

  def init do
    %{
      text: "",
      value: :dl
    }
  end

  def template do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <title>Hologram E2E</title>
        <Hologram.UI.Runtime />
      </head>
      <body>
        <div id="text-default-layout">{@text}</div>
        default layout:
        <slot />
      </body>
    </html>
    """
  end

  def action(:default_layout_action_1, _params, state) do
    {update(state, :text, "text updated by default_layout_action_1, state.value = #{state.value}")}
  end
end
