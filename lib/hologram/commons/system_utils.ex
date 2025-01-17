defmodule Hologram.Commons.SystemUtils do
  @moduledoc false

  alias Hologram.Commons.IntegerUtils

  @doc """
  Returns the OTP major version.
  """
  @spec otp_version :: integer
  def otp_version do
    IntegerUtils.parse!(System.otp_release())
  end
end
