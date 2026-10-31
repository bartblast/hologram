defmodule HologramFeatureTests.Queries.Page8 do
  use Hologram.Page
  use Hologram.DB

  alias HologramFeatureTests.Components.Queries.Component16
  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label

  route "/queries/8"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:local_messages, nil)
    |> put_state(:unrendered_channel_name, "random")
    |> put_state(:unrendered_label_name, "later")
  end

  def template do
    ~HOLO"""
    <Component16 cid="component_16" channel_name="general" label_name="urgent" />
    <p>
      <button $click="read_unrendered_messages_locally">Read unrendered messages locally</button>
    </p>
    {%if @local_messages}
      <p>
        Local unrendered messages: <strong id="local_unrendered_messages"><code>{@local_messages}</code></strong>
      </p>
    {/if}
    """
  end

  # The read runs in the browser over the channel and the label the component never renders - the
  # render hands over none of their messages or the channel's topic, so the answer can only come
  # from what the stream filled in through the inverses.
  def action(:read_unrendered_messages_locally, _params, component) do
    channel_name = component.state.unrendered_channel_name
    label_name = component.state.unrendered_label_name

    [channel] =
      Channel
      |> filter(name == ^channel_name)
      |> include([messages, topic])
      |> DB.read()

    [label] =
      Label
      |> filter(name == ^label_name)
      |> include(messages)
      |> DB.read()

    channel_bodies = Enum.map_join(channel.messages, ",", & &1.body)

    label_bodies =
      label.messages
      |> Enum.map(& &1.body)
      |> Enum.sort()
      |> Enum.join(",")

    put_state(
      component,
      :local_messages,
      "#{channel_bodies}/#{channel.topic.title}; #{label_bodies}"
    )
  end
end
