defmodule Demo.Repo do
  use Ecto.Repo,
    otp_app: :hologram,
    adapter: Ecto.Adapters.Postgres
end
