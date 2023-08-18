defmodule Hologram.Router.SearchTreeTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Router.SearchTree
  alias Hologram.Router.SearchTree

  defp build_search_tree_fixture do
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
        {"/ccc/:param/ddd", :page_ccc_param_ddd},
        {"/ccc/ddd/:param", :page_ccc_ddd_param}
      ])

    Enum.reduce(routes, %SearchTree.Node{}, fn {url_path, page_module}, acc ->
      add_route(acc, url_path, page_module)
    end)
  end

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
      assert build_search_tree_fixture() == %SearchTree.Node{
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

  describe "match_route/2" do
    setup do
      [search_tree: build_search_tree_fixture()]
    end

    test "/", %{search_tree: search_tree} do
      assert match_route(search_tree, "/") == :page_root
    end

    test "/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa") == :page_aaa
    end

    test "/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz") == :page_param
    end

    test "/aaa/bbb", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/bbb") == :page_aaa_bbb
    end

    test "/aaa/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/xyz") == :page_aaa_param
    end

    test "/:param/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/aaa") == :page_param_aaa
    end

    test "/ccc/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/ccc/aaa") == :page_ccc_aaa
    end

    test "/ccc/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/ccc/xyz") == :page_ccc_param
    end

    test "/aaa/bbb/ccc", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/bbb/ccc") == :page_aaa_bbb_ccc
    end

    test "/:param/aaa/bbb", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/aaa/bbb") == :page_param_aaa_bbb
    end

    test "/aaa/:param/bbb", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/xyz/bbb") == :page_aaa_param_bbb
    end

    test "/aaa/bbb/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/bbb/xyz") == :page_aaa_bbb_param
    end

    test "/ccc/ddd/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/ccc/ddd/aaa") == :page_ccc_ddd_aaa
    end

    test "/:param/ccc/ddd", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/ccc/ddd") == :page_param_ccc_ddd
    end

    test "/ccc/:param/ddd", %{search_tree: search_tree} do
      assert match_route(search_tree, "/ccc/xyz/ddd") == :page_ccc_param_ddd
    end

    test "/ccc/ddd/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/ccc/ddd/xyz") == :page_ccc_ddd_param
    end

    test "/eee" do
      search_tree = add_route(%SearchTree.Node{}, "/aaa", :page_aaa)

      assert match_route(search_tree, "/eee") == false
    end

    test "/aaa/eee" do
      search_tree = add_route(%SearchTree.Node{}, "/aaa/bbb", :page_aaa_bbb)

      assert match_route(search_tree, "/aaa/eee") == false
    end

    test "/eee/aaa" do
      search_tree = add_route(%SearchTree.Node{}, "/bbb/aaa", :page_bbb_aaa)

      assert match_route(search_tree, "/eee/aaa") == false
    end

    test "/:param/eee", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/eee") == false
    end

    test "/eee/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/eee/xyz") == false
    end

    test "/eee/aaa/bbb" do
      search_tree = add_route(%SearchTree.Node{}, "/ccc/aaa/bbb", :page_ccc_aaa_bbb)

      assert match_route(search_tree, "/eee/aaa/bbb") == false
    end

    test "/aaa/eee/bbb" do
      search_tree = add_route(%SearchTree.Node{}, "/aaa/ccc/bbb", :page_aaa_ccc_bbb)

      assert match_route(search_tree, "/aaa/eee/bbb") == false
    end

    test "/aaa/bbb/eee" do
      search_tree = add_route(%SearchTree.Node{}, "/aaa/bbb/ccc", :page_aaa_bbb_ccc)

      assert match_route(search_tree, "/aaa/bbb/eee") == false
    end

    test "/eee/aaa/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/eee/aaa/xyz") == false
    end

    test "/eee/:param/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/eee/xyz/aaa") == false
    end

    test "/aaa/eee/:param", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/eee/xyz") == false
    end

    test "/:param/eee/aaa", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/eee/aaa") == false
    end

    test "/aaa/:param/eee", %{search_tree: search_tree} do
      assert match_route(search_tree, "/aaa/xyz/eee") == false
    end

    test "/:param/aaa/eee", %{search_tree: search_tree} do
      assert match_route(search_tree, "/xyz/aaa/eee") == false
    end

    test "no root route" do
      assert match_route(%SearchTree.Node{}, "/") == false
    end
  end
end
