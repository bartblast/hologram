# Elixir Benchmarks

Last run: 2026-09-17 12:01:09 UTC

## Summary

Total benchmarks: 38

Successful: 38\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          1.81      551.54 ms     ±3.17%      552.08 ms      581.32 ms
```


### ✅ compiler » build_app_versions_1

```
Name                           ips        average  deviation         median         99th %
build_app_versions/1         17.86       55.98 ms     ±2.32%       55.63 ms       63.77 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          1.78      562.33 ms     ±6.51%      550.33 ms      649.67 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          1.03      968.84 ms     ±4.77%      950.83 ms     1059.61 ms
```


### ✅ compiler » build_module_info_plt!_2

```
Name                                                          ips        average  deviation         median         99th %
previous dump, nothing changed (every entry reused)          9.15      109.29 ms     ±5.11%      107.88 ms      126.94 ms
no previous dump (every beam read)                           5.68      176.17 ms     ±4.96%      173.87 ms      210.96 ms

Comparison: 
previous dump, nothing changed (every entry reused)          9.15
no previous dump (every beam read)                           5.68 - 1.61x slower +66.88 ms
```


### ✅ compiler » build_module_metadata_1

```
Name                              ips        average  deviation         median         99th %
build_module_metadata/1        345.77        2.89 ms    ±10.43%        2.84 ms        3.76 ms
```


### ✅ compiler » build_page_js_5

```
Name                      ips        average  deviation         median         99th %
build_page_js/5        214.18        4.67 ms    ±12.03%        4.55 ms        5.57 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          3.19      313.84 ms     ±5.52%      316.81 ms      335.77 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         37.21       26.87 ms    ±15.21%       24.03 ms       33.87 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                17.27       57.89 ms     ±4.36%       57.10 ms       75.79 ms
dump dir doesn't exists                          17.22       58.06 ms     ±4.14%       57.47 ms       74.25 ms
dump dir exists, dump file doesn't exist         17.20       58.14 ms     ±4.19%       57.47 ms       75.62 ms

Comparison: 
dump dir exists, dump file exists                17.27
dump dir doesn't exists                          17.22 - 1.00x slower +0.172 ms
dump dir exists, dump file doesn't exist         17.20 - 1.00x slower +0.25 ms
```


### ✅ compiler » call_graph » list_page_mfas_4

```
Name                       ips        average  deviation         median         99th %
list_page_mfas/4        570.04        1.75 ms     ±7.29%        1.74 ms        1.88 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_2

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/2         42.80       23.37 ms    ±18.60%       25.17 ms       29.31 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                       22751.01      0.0440 ms    ±11.70%      0.0424 ms      0.0564 ms
1 module removed                          132.79        7.53 ms    ±59.80%        5.07 ms       19.63 ms
1 module added                            115.04        8.69 ms     ±9.10%        8.48 ms       10.84 ms
1 module edited                            57.83       17.29 ms    ±28.62%       14.55 ms       29.34 ms
1 added, 1 removed, 1 edited               47.67       20.98 ms    ±22.31%       19.18 ms       33.60 ms
3 added, 3 removed, 3 edited               31.92       31.33 ms    ±16.46%       33.33 ms       39.20 ms
10 added, 10 removed, 10 edited            11.57       86.46 ms     ±7.03%       85.39 ms       98.43 ms
1% added, 1% removed, 1% edited             9.98      100.21 ms     ±7.06%       97.71 ms      112.14 ms
100% modules added                          3.63      275.69 ms     ±9.13%      272.34 ms      329.95 ms
100% modules removed                        0.76     1307.56 ms     ±0.46%     1305.27 ms     1319.59 ms
33% added, 33% removed, 34% edited          0.68     1472.22 ms     ±0.43%     1472.37 ms     1482.58 ms
100% modules edited                         0.20     4939.73 ms     ±0.14%     4939.73 ms     4944.58 ms

Comparison: 
no module changes                       22751.01
1 module removed                          132.79 - 171.33x slower +7.49 ms
1 module added                            115.04 - 197.77x slower +8.65 ms
1 module edited                            57.83 - 393.40x slower +17.25 ms
1 added, 1 removed, 1 edited               47.67 - 477.24x slower +20.93 ms
3 added, 3 removed, 3 edited               31.92 - 712.83x slower +31.29 ms
10 added, 10 removed, 10 edited            11.57 - 1967.00x slower +86.41 ms
1% added, 1% removed, 1% edited             9.98 - 2279.91x slower +100.17 ms
100% modules added                          3.63 - 6272.27x slower +275.65 ms
100% modules removed                        0.76 - 29748.28x slower +1307.51 ms
33% added, 33% removed, 34% edited          0.68 - 33494.40x slower +1472.17 ms
100% modules edited                         0.20 - 112383.91x slower +4939.69 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        1.37 M      729.21 ns    ±50.83%         667 ns     2441.36 ns
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       45.93 K       21.77 μs     ±5.64%       21.54 μs       29.63 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
1 vertex        1223.41 K        0.82 μs    ±45.44%        0.75 μs        2.80 μs
2 vertices      1021.14 K        0.98 μs    ±37.39%        0.92 μs        2.97 μs
4 vertices       951.39 K        1.05 μs    ±29.82%           1 μs        2.69 μs
8 vertices       818.56 K        1.22 μs    ±19.47%        1.21 μs        2.13 μs
16 vertices      645.65 K        1.55 μs    ±18.91%        1.50 μs        2.65 μs
32 vertices      377.95 K        2.65 μs    ±17.06%        2.54 μs        4.96 μs

Comparison: 
1 vertex        1223.41 K
2 vertices      1021.14 K - 1.20x slower +0.162 μs
4 vertices       951.39 K - 1.29x slower +0.23 μs
8 vertices       818.56 K - 1.49x slower +0.40 μs
16 vertices      645.65 K - 1.89x slower +0.73 μs
32 vertices      377.95 K - 3.24x slower +1.83 μs
```


### ✅ compiler » call_graph » server_callback_analysis_by_templatable_3

```
Name                                                ips        average  deviation         median         99th %
server_callback_analysis_by_templatable/3        6.73 K      148.57 μs    ±13.37%         146 μs      170.33 μs
```


### ✅ compiler » call_graph » server_protocol_dispatch_types_3

```
Name                       ips        average  deviation         median         99th %
1 templatable           3.51 K      284.68 μs    ±18.39%      279.79 μs      319.46 μs
all templatables        3.01 K      332.74 μs    ±18.98%      325.88 μs      392.50 μs

Comparison: 
1 templatable           3.51 K
all templatables        3.01 K - 1.17x slower +48.06 μs
```


### ✅ compiler » create_page_entry_files_7

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/7          1.20      836.37 ms     ±3.82%      833.46 ms      905.31 ms
```


### ✅ compiler » create_runtime_entry_file_6

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/6          9.25      108.12 ms     ±5.79%      107.22 ms      137.40 ms
```


### ✅ compiler » diff_module_info_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                     1858.32        0.54 ms    ±18.03%        0.62 ms        0.65 ms
100% modules added                       1616.13        0.62 ms    ±19.50%        0.71 ms        0.86 ms
33% added, 33% removed, 34% edited       1273.18        0.79 ms     ±3.12%        0.78 ms        0.85 ms
3 added, 3 removed, 3 edited              826.25        1.21 ms     ±4.05%        1.20 ms        1.32 ms
no module changes                         822.59        1.22 ms     ±4.25%        1.21 ms        1.46 ms
1 added, 1 removed, 1 edited              820.39        1.22 ms     ±4.48%        1.21 ms        1.33 ms
1 module added                            816.52        1.22 ms     ±4.06%        1.22 ms        1.45 ms
1 module edited                           812.37        1.23 ms     ±7.74%        1.22 ms        1.41 ms
1% added, 1% removed, 1% edited           774.03        1.29 ms     ±5.43%        1.31 ms        1.51 ms
1 module removed                          768.55        1.30 ms     ±5.94%        1.31 ms        1.51 ms
10 added, 10 removed, 10 edited           764.02        1.31 ms     ±5.49%        1.33 ms        1.48 ms
100% modules edited                       717.28        1.39 ms     ±4.42%        1.41 ms        1.57 ms

Comparison: 
100% modules removed                     1858.32
100% modules added                       1616.13 - 1.15x slower +0.0806 ms
33% added, 33% removed, 34% edited       1273.18 - 1.46x slower +0.25 ms
3 added, 3 removed, 3 edited              826.25 - 2.25x slower +0.67 ms
no module changes                         822.59 - 2.26x slower +0.68 ms
1 added, 1 removed, 1 edited              820.39 - 2.27x slower +0.68 ms
1 module added                            816.52 - 2.28x slower +0.69 ms
1 module edited                           812.37 - 2.29x slower +0.69 ms
1% added, 1% removed, 1% edited           774.03 - 2.40x slower +0.75 ms
1 module removed                          768.55 - 2.42x slower +0.76 ms
10 added, 10 removed, 10 edited           764.02 - 2.43x slower +0.77 ms
100% modules edited                       717.28 - 2.59x slower +0.86 ms
```


### ✅ compiler » encode_reachable_functions_5

```
Name                                   ips        average  deviation         median         99th %
encode_reachable_functions/5         57.65       17.35 ms     ±5.26%       17.06 ms       19.72 ms
```


### ✅ compiler » encoder » encode_term!_1

```
Name                                     ips        average  deviation         median         99th %
10 KB of text                       12393.06      0.0807 ms    ±10.55%      0.0748 ms       0.108 ms
200 KB binary that is not text       2754.18        0.36 ms     ±2.40%        0.36 ms        0.38 ms
80 KB of text                        1530.09        0.65 ms     ±3.93%        0.65 ms        0.71 ms
256 KB of non-ASCII text              680.12        1.47 ms     ±1.98%        1.47 ms        1.54 ms
160 KB of text                        623.51        1.60 ms     ±1.37%        1.60 ms        1.67 ms
320 KB of text                        319.21        3.13 ms     ±3.63%        3.11 ms        3.47 ms
640 KB of text                        146.78        6.81 ms     ±2.72%        6.84 ms        7.18 ms

Comparison: 
10 KB of text                       12393.06
200 KB binary that is not text       2754.18 - 4.50x slower +0.28 ms
80 KB of text                        1530.09 - 8.10x slower +0.57 ms
256 KB of non-ASCII text              680.12 - 18.22x slower +1.39 ms
160 KB of text                        623.51 - 19.88x slower +1.52 ms
320 KB of text                        319.21 - 38.82x slower +3.05 ms
640 KB of text                        146.78 - 84.43x slower +6.73 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        7.03 K      0.00014 s    ±12.24%      0.00014 s      0.00020 s
do install     0.00018 K         5.65 s     ±7.05%         5.65 s         5.94 s

Comparison: 
no install        7.03 K
do install     0.00018 K - 39751.25x slower +5.65 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      165.33 K     0.00605 ms   ±186.16%     0.00546 ms      0.0140 ms
do load      0.0105 K       95.38 ms     ±7.81%       94.43 ms      127.89 ms

Comparison: 
no load      165.33 K
do load      0.0105 K - 15769.59x slower +95.38 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load       76.52 K      0.0131 ms    ±59.81%      0.0119 ms      0.0216 ms
do load     0.00149 K      673.23 ms     ±2.18%      666.55 ms      700.15 ms

Comparison: 
no load       76.52 K
do load     0.00149 K - 51512.78x slower +673.21 ms
```


### ✅ compiler » maybe_load_module_info_plt_1

```
Name              ips        average  deviation         median         99th %
no load       64.12 K      0.0156 ms    ±53.27%      0.0140 ms      0.0345 ms
do load        0.31 K        3.26 ms     ±2.99%        3.24 ms        3.62 ms

Comparison: 
no load       64.12 K
do load        0.31 K - 208.97x slower +3.24 ms
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1         42.99       23.26 ms     ±4.34%       23.02 ms       28.04 ms
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache          0.51         1.96 s     ±9.24%         1.87 s         2.31 s
no cache          0.185         5.39 s     ±3.78%         5.39 s         5.54 s

Comparison: 
has cache          0.51
no cache          0.185 - 2.75x slower +3.43 s
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           130.58 M        7.66 ns  ±5356.03%        8.30 ns       16.60 ns
is Erlang module       10.28 M       97.31 ns ±10578.02%          42 ns         125 ns
is atom                10.25 M       97.52 ns ±10613.67%          42 ns         125 ns
is Elixir module      0.0113 M    88420.67 ns   ±137.18%       79500 ns   198527.72 ns

Comparison: 
is not atom           130.58 M
is Erlang module       10.28 M - 12.71x slower +89.65 ns
is atom                10.25 M - 12.73x slower +89.86 ns
is Elixir module      0.0113 M - 11545.87x slower +88413.01 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            24.13 M      0.0414 μs    ±34.67%      0.0420 μs      0.0420 μs
is Erlang module        2.11 M        0.47 μs  ±1818.67%        0.42 μs        0.58 μs
is atom               0.0561 M       17.82 μs   ±128.48%       15.54 μs       38.50 μs
is Elixir module     0.00915 M      109.33 μs    ±58.77%      103.25 μs      182.46 μs

Comparison: 
is not atom            24.13 M
is Erlang module        2.11 M - 11.46x slower +0.43 μs
is atom               0.0561 M - 429.95x slower +17.77 μs
is Elixir module     0.00915 M - 2638.54x slower +109.29 μs
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3        3.84 M      260.61 ns  ±3400.29%         208 ns         292 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1        3.36 K      297.41 μs   ±245.63%      278.54 μs      438.82 μs
```


### ✅ reflection » list_components_0

```
Name                        ips        average  deviation         median         99th %
list_components/0          1.56      640.28 ms    ±16.28%      595.18 ms     1007.60 ms
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0          4.19      238.81 ms     ±6.60%      231.56 ms      272.41 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0          1.34      744.16 ms    ±20.88%      695.32 ms     1247.34 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        132.84        7.53 ms    ±11.27%        7.43 ms        9.56 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           107.17 M     0.00933 μs ±20676.60%     0.00830 μs      0.0167 μs
is Erlang module        3.78 M        0.26 μs  ±2594.29%        0.21 μs        0.33 μs
is Elixir module      0.0514 M       19.46 μs    ±41.84%       16.96 μs       45.83 μs
is atom               0.0504 M       19.82 μs    ±72.83%       16.54 μs       45.04 μs

Comparison: 
is not atom           107.17 M
is Erlang module        3.78 M - 28.36x slower +0.26 μs
is Elixir module      0.0514 M - 2085.22x slower +19.45 μs
is atom               0.0504 M - 2124.31x slower +19.81 μs
```

