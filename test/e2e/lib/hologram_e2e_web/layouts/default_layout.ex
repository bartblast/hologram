defmodule HologramE2E.DefaultLayout do
  use Hologram.Layout

  def init(_conn) do
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
    {put(state, :text, "text updated by default_layout_action_1, state.value = #{state.value}")}
  end

  def action(:default_layout_action_2_b, _params, state) do
    {put(
       state,
       :text,
       "text updated by default_layout_action_2_b, state.value = #{state.value}"
     )}
  end

  def command(:default_layout_command_1, _params) do
    :default_layout_action_2_b
  end
end
