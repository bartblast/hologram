defmodule HologramFeatureTests.Security.Page5 do
  use Hologram.Page

  route "/security/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, email: nil, select: nil, text: nil, textarea: nil)
  end

  def template do
    ~HOLO"""
    <form>
      <input type="text" id="text_input" value={@text} />
      <div id="text_result">{@text}</div>
      <br /><br />
      
      <input type="email" id="email_input" value={@email} />
      <div id="email_result">{@email}</div>
      <br /><br />
      
      <textarea type="textarea" id="textarea_input" value={@textarea} />
      <div id="textarea_result">{@textarea}</div>
      <br /><br />
      
      <select id="select_input" value={@select}>
        <option id="select_option_1" value="option_1">Option 1</option>
        <option id="select_option_2" value="b < c">Option 2</option>
        <option id="select_option_3" value="option_2">Option 2</option>
      </select>
      <div id="select_result">{@select}</div>
    </form>

    <p>
      <button $click="set_values">Set values</button>
    </p>
    """
  end

  def action(:set_values, _params, component) do
    put_state(component, email: "c < d", select: "b < c", text: "a < b", textarea: "d < e")
  end
end
