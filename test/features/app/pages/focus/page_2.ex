defmodule HologramFeatureTests.Focus.Page2 do
  use Hologram.Page

  route "/focus/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      blocked?: false,
      editing?: false,
      late?: false,
      locked?: true,
      order?: false,
      pair?: false
    )
  end

  # The blocked section's first candidate is a disabled button, which can't take focus, so the
  # field after it has to.
  #
  # The unlocked field is enabled and declared focused by the same render. The patch removes the
  # disabled attribute before focus is settled, so the field can take it.
  #
  # The order section asks for focus twice in one render: the later field is kept and turns its
  # declaration on, which Snabbdom reports during the patch, while the earlier one is inserted,
  # which it reports after the patch. The earlier one is collected last, so only a document-order
  # rule picks it.
  def template do
    ~HOLO"""
    <p>
      <button $click="edit">Edit</button>
      <button $click="show_blocked">Show blocked</button>
      <button $click="show_late">Show late</button>
      <button $click="show_order">Show order</button>
      <button $click="show_pair">Show pair</button>
      <button $click="unlock">Unlock</button>
    </p>
    {%if @blocked?}
      <p>
        <button id="page_2_disabled" disabled $focused={true}>Disabled</button>
        <input type="text" id="page_2_after_disabled" $focused={true} />
      </p>
    {/if}
    <p>
      <input type="text" id="page_2_unlocked" disabled={@locked?} $focused={!@locked?} />
    </p>
    {%if @editing?}
      <p><input type="text" id="page_2_editor" $focused={true} /></p>
    {/if}
    {%if @late?}
      <p><input type="text" id="page_2_late" autofocus /></p>
    {/if}
    <p>
      {%if @order?}
        <input type="text" id="page_2_order_early" $focused={true} />
      {/if}
      <input type="text" id="page_2_order_late" $focused={@order?} />
    </p>
    {%if @pair?}
      <p>
        <input type="text" id="page_2_first" $focused={true} />
        <input type="text" id="page_2_second" $focused={true} />
      </p>
    {/if}
    """
  end

  def action(:edit, _params, component) do
    put_state(component, :editing?, true)
  end

  def action(:show_blocked, _params, component) do
    put_state(component, :blocked?, true)
  end

  def action(:show_late, _params, component) do
    put_state(component, :late?, true)
  end

  def action(:show_order, _params, component) do
    put_state(component, :order?, true)
  end

  def action(:show_pair, _params, component) do
    put_state(component, :pair?, true)
  end

  def action(:unlock, _params, component) do
    put_state(component, :locked?, false)
  end
end
