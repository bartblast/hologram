defmodule Hologram.Mutation.ClockAllowanceTest do
  # async: false - the allowance is read from the application environment, which is one value for
  # the whole node, so a test that sets it cannot run beside the ones that lean on the default.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Mutation

  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Policy.Module2

  defp envelope(stamp) do
    %{
      "instance_id" => "i1",
      "client_id" => Entity.generate_id(),
      "model_hash" => Model.hash(),
      "seq" => 1,
      "writes" => [
        %{
          "op" => "create",
          "type" => inspect(Module2),
          "id" => Entity.generate_id(),
          "data" => %{"public" => true},
          "claim" => ["authorize", "publish"],
          "stamp" => stamp
        }
      ]
    }
  end

  describe "run/2" do
    test "reads the clock allowance from the application environment" do
      put_app_env(:mutation, clock_allowance_ms: 0)

      a_second_ahead = (System.os_time(:millisecond) + 1_000) * 1024

      assert run(envelope(a_second_ahead), %Server{}) == {:rejected, 0, :clock}
    end
  end
end
