defmodule Hologram.Config do
  def init(_otp_app, _env) do
    Application.put_env(:hologram, :mode, :standalone)
  end
end
