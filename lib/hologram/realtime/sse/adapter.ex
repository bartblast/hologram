defmodule Hologram.Realtime.SSE.Adapter do
  @moduledoc false

  # What the realtime stream needs to know about the server it runs on: how a client that
  # has gone away shows up in the pump's mailbox. That is the only thing that differs
  # between servers, so it is the only thing an adapter answers.

  @doc """
  Classifies a mailbox message the pump doesn't recognise: `:closed` ends the stream,
  `:ignore` leaves it running. Any hand-back the server needs for the message happens here.
  """
  @callback handle_message(term) :: :closed | :ignore

  @doc """
  Arms whatever the server needs so that a departed client arrives in the pump's mailbox.
  Called once, right after the stream's response is opened.
  """
  @callback watch(Plug.Conn.t()) :: :ok
end
