defmodule Demo.Repo do
  use Ecto.Repo,
    otp_app: :holograf,
    adapter: Ecto.Adapters.Postgres
end
