defmodule Hologram.Commons.SystemUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.SystemUtils

  test "otp_version/0" do
    assert to_string(otp_version()) == System.otp_release()
  end
end
