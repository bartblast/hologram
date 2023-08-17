defmodule Hologram.Runtime.TemplatableTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Templatable

  test "colocated_template_path/1" do
    colocated_template_path("/my_dir_1/my_dir_2/my_dir_3/my_file.ex") ==
      "/my_dir_1/my_dir_2/my_dir_3/my_file.holo"
  end
end
