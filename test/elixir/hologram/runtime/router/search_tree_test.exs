defmodule Hologram.Router.SearchTreeTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router.SearchTree
  alias Hologram.Router.SearchTree

  describe "add_route/3" do
    test "/" do
      result = add_route(%SearchTree.Node{}, "/", :page_root)

      assert result == %SearchTree.Node{
               value: :page_root,
               children: %{}
             }
    end

    test "/aaa" do
      result = add_route(%SearchTree.Node{}, "/aaa", :page_aaa)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{value: :page_aaa, children: %{}}
               }
             }
    end

    test "/:param" do
      result = add_route(%SearchTree.Node{}, "/:param", :page_param)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "*" => %SearchTree.Node{value: :page_param, children: %{}}
               }
             }
    end

    test "/aaa/bbb" do
      result = add_route(%SearchTree.Node{}, "/aaa/bbb", :page_aaa_bbb)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "bbb" => %SearchTree.Node{
                       value: :page_aaa_bbb,
                       children: %{}
                     }
                   }
                 }
               }
             }
    end

    test "/aaa/:param" do
      result = add_route(%SearchTree.Node{}, "/aaa/:param", :page_aaa_param)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "*" => %SearchTree.Node{
                       value: :page_aaa_param,
                       children: %{}
                     }
                   }
                 }
               }
             }
    end

    test "/:param/aaa" do
      result = add_route(%SearchTree.Node{}, "/:param/aaa", :page_param_aaa)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "*" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "aaa" => %SearchTree.Node{
                       value: :page_param_aaa,
                       children: %{}
                     }
                   }
                 }
               }
             }
    end

    test "/aaa/bbb/ccc" do
      result = add_route(%SearchTree.Node{}, "/aaa/bbb/ccc", :page_aaa_bbb_ccc)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "bbb" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "ccc" => %SearchTree.Node{
                           value: :page_aaa_bbb_ccc,
                           children: %{}
                         }
                       }
                     }
                   }
                 }
               }
             }
    end

    test "/:param/aaa/bbb" do
      result = add_route(%SearchTree.Node{}, "/:param/aaa/bbb", :page_param_aaa_bbb)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "*" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "aaa" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "bbb" => %SearchTree.Node{
                           value: :page_param_aaa_bbb,
                           children: %{}
                         }
                       }
                     }
                   }
                 }
               }
             }
    end

    test "/aaa/:param/bbb" do
      result = add_route(%SearchTree.Node{}, "/aaa/:param/bbb", :page_aaa_param_bbb)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "*" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "bbb" => %SearchTree.Node{
                           value: :page_aaa_param_bbb,
                           children: %{}
                         }
                       }
                     }
                   }
                 }
               }
             }
    end

    test "/aaa/bbb/:param" do
      result = add_route(%SearchTree.Node{}, "/aaa/bbb/:param", :page_aaa_bbb_param)

      assert result == %SearchTree.Node{
               value: nil,
               children: %{
                 "aaa" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "bbb" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "*" => %SearchTree.Node{
                           value: :page_aaa_bbb_param,
                           children: %{}
                         }
                       }
                     }
                   }
                 }
               }
             }
    end

    test "multiple routes" do
      routes =
        Enum.shuffle([
          {"/", :page_root},
          {"/aaa", :page_aaa},
          {"/:param", :page_param},
          {"/aaa/bbb", :page_aaa_bbb},
          {"/aaa/:param", :page_aaa_param},
          {"/:param/aaa", :page_param_aaa},
          {"/ccc/aaa", :page_ccc_aaa},
          {"/ccc/:param", :page_ccc_param},
          {"/aaa/bbb/ccc", :page_aaa_bbb_ccc},
          {"/:param/aaa/bbb", :page_param_aaa_bbb},
          {"/aaa/:param/bbb", :page_aaa_param_bbb},
          {"/aaa/bbb/:param", :page_aaa_bbb_param},
          {"/ccc/ddd/aaa", :page_ccc_ddd_aaa},
          {"/:param/ccc/ddd", :page_param_ccc_ddd},
          {"ccc/:param/ddd", :page_ccc_param_ddd},
          {"ccc/ddd/:param", :page_ccc_ddd_param}
        ])

      result =
        Enum.reduce(routes, %SearchTree.Node{}, fn {url_path, page_module}, acc ->
          add_route(acc, url_path, page_module)
        end)

      assert result == %SearchTree.Node{
               value: :page_root,
               children: %{
                 "*" => %SearchTree.Node{
                   value: :page_param,
                   children: %{
                     "aaa" => %SearchTree.Node{
                       value: :page_param_aaa,
                       children: %{
                         "bbb" => %SearchTree.Node{
                           value: :page_param_aaa_bbb,
                           children: %{}
                         }
                       }
                     },
                     "ccc" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "ddd" => %SearchTree.Node{
                           value: :page_param_ccc_ddd,
                           children: %{}
                         }
                       }
                     }
                   }
                 },
                 "aaa" => %SearchTree.Node{
                   value: :page_aaa,
                   children: %{
                     "*" => %SearchTree.Node{
                       value: :page_aaa_param,
                       children: %{
                         "bbb" => %SearchTree.Node{
                           value: :page_aaa_param_bbb,
                           children: %{}
                         }
                       }
                     },
                     "bbb" => %SearchTree.Node{
                       value: :page_aaa_bbb,
                       children: %{
                         "*" => %SearchTree.Node{
                           value: :page_aaa_bbb_param,
                           children: %{}
                         },
                         "ccc" => %SearchTree.Node{
                           value: :page_aaa_bbb_ccc,
                           children: %{}
                         }
                       }
                     }
                   }
                 },
                 "ccc" => %SearchTree.Node{
                   value: nil,
                   children: %{
                     "*" => %SearchTree.Node{
                       value: :page_ccc_param,
                       children: %{
                         "ddd" => %SearchTree.Node{
                           value: :page_ccc_param_ddd,
                           children: %{}
                         }
                       }
                     },
                     "aaa" => %SearchTree.Node{
                       value: :page_ccc_aaa,
                       children: %{}
                     },
                     "ddd" => %SearchTree.Node{
                       value: nil,
                       children: %{
                         "*" => %SearchTree.Node{
                           value: :page_ccc_ddd_param,
                           children: %{}
                         },
                         "aaa" => %SearchTree.Node{
                           value: :page_ccc_ddd_aaa,
                           children: %{}
                         }
                       }
                     }
                   }
                 }
               }
             }
    end
  end
end
