defmodule Hologram.HTTP do
  use Plug.Builder

  plug Plug.Static,
    at: "/",
    from: {Hologram.Reflection.otp_app(), "priv/dist"}

  plug Hologram.Router
end
