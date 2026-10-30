# Elixir Benchmarks

Last run: 2026-10-11 23:08:28 UTC

## Summary

Total benchmarks: 46

Successful: 46\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          1.48      675.67 ms    ±10.27%      645.65 ms      844.92 ms
```


### ✅ compiler » build_app_versions_1

```
Name                           ips        average  deviation         median         99th %
build_app_versions/1         14.40       69.47 ms     ±1.86%       69.16 ms       79.84 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          1.40      712.53 ms     ±4.91%      719.47 ms      746.02 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          1.37      728.76 ms     ±1.47%      727.00 ms      754.24 ms
```


### ✅ compiler » build_kept_page_reach_3

```
Name                              ips        average  deviation         median         99th %
build_kept_page_reach/3        565.97        1.77 ms    ±11.77%        1.72 ms        2.41 ms
```


### ✅ compiler » build_missing_ir!_2

```
Name                      ips        average  deviation         median         99th %
nothing missing        7.90 K       0.127 ms     ±3.22%       0.126 ms       0.140 ms
all missing         0.00156 K      640.21 ms     ±3.49%      633.59 ms      708.84 ms

Comparison: 
nothing missing        7.90 K
all missing         0.00156 K - 5054.65x slower +640.08 ms
```


### ✅ compiler » build_module_info_plt!_2

```
Name                                                          ips        average  deviation         median         99th %
previous dump, nothing changed (every entry reused)         10.31       96.97 ms     ±2.24%       96.49 ms      107.17 ms
no previous dump (every beam read)                           5.29      189.00 ms     ±2.36%      188.35 ms      210.23 ms

Comparison: 
previous dump, nothing changed (every entry reused)         10.31
no previous dump (every beam read)                           5.29 - 1.95x slower +92.03 ms
```


### ✅ compiler » build_module_metadata_1

```
Name                              ips        average  deviation         median         99th %
build_module_metadata/1        372.80        2.68 ms    ±10.54%        2.55 ms        3.60 ms
```


### ✅ compiler » build_page_js_5

```
Name                      ips        average  deviation         median         99th %
build_page_js/5        233.59        4.28 ms    ±12.15%        4.30 ms        5.32 ms
```


### ✅ compiler » build_page_windows_3

```
Name                           ips        average  deviation         median         99th %
build_page_windows/3        6.64 K      150.53 μs    ±10.67%      147.13 μs      184.17 μs
```


### ✅ compiler » build_queries_3

```
Name                      ips        average  deviation         median         99th %
build_queries/3       18.46 K       54.17 μs    ±15.05%       51.46 μs       82.92 μs
```


### ✅ compiler » build_sync_constants_3

```
Name                             ips        average  deviation         median         99th %
build_sync_constants/3        2.17 K      460.90 μs     ±8.88%      454.92 μs      549.11 μs
```


### ✅ compiler » build_sync_constants_js_1

```
Name                                ips        average  deviation         median         99th %
build_sync_constants_js/1          2.38      420.59 ms     ±2.90%      420.75 ms      444.66 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          2.74      364.74 ms     ±1.90%      362.61 ms      382.42 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         30.66       32.61 ms    ±13.90%       29.58 ms       40.45 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir doesn't exists                          14.00       71.44 ms     ±7.50%       69.94 ms      105.19 ms
dump dir exists, dump file exists                13.82       72.37 ms     ±8.08%       70.57 ms      110.78 ms
dump dir exists, dump file doesn't exist         13.80       72.47 ms    ±15.80%       69.42 ms      156.60 ms

Comparison: 
dump dir doesn't exists                          14.00
dump dir exists, dump file exists                13.82 - 1.01x slower +0.94 ms
dump dir exists, dump file doesn't exist         13.80 - 1.01x slower +1.04 ms
```


### ✅ compiler » call_graph » list_modules_reaching_2

```
Name                    ips        average  deviation         median         99th %
1 leaf module       1140.45        0.88 ms     ±5.89%        0.86 ms        1.10 ms
1 core module        828.84        1.21 ms    ±12.95%        1.13 ms        1.77 ms
10 modules            10.47       95.49 ms     ±3.59%       94.43 ms      113.20 ms

Comparison: 
1 leaf module       1140.45
1 core module        828.84 - 1.38x slower +0.33 ms
10 modules            10.47 - 108.90x slower +94.61 ms
```


### ✅ compiler » call_graph » list_page_mfas_4

```
Name                       ips        average  deviation         median         99th %
list_page_mfas/4        611.53        1.64 ms    ±19.59%        1.58 ms        2.13 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1        308.21        3.24 ms    ±11.32%        3.13 ms        4.11 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                       17733.43      0.0564 ms    ±21.76%      0.0513 ms      0.0919 ms
1 module added                          10980.55      0.0911 ms    ±12.24%      0.0884 ms       0.119 ms
1 module removed                           91.52       10.93 ms    ±96.67%        4.12 ms       27.26 ms
1 module edited                            82.97       12.05 ms    ±76.76%        6.90 ms       29.56 ms
1 added, 1 removed, 1 edited               78.18       12.79 ms    ±65.49%        9.01 ms       33.07 ms
3 added, 3 removed, 3 edited               44.10       22.67 ms    ±43.10%       17.50 ms       41.41 ms
10 added, 10 removed, 10 edited            18.58       53.83 ms    ±17.12%       50.19 ms       71.67 ms
1% added, 1% removed, 1% edited             9.25      108.09 ms     ±9.95%      101.86 ms      126.58 ms
100% modules added                          5.31      188.48 ms     ±5.70%      187.78 ms      218.36 ms
100% modules removed                        0.52     1917.03 ms     ±1.44%     1912.47 ms     1957.76 ms
33% added, 33% removed, 34% edited          0.51     1954.29 ms     ±0.73%     1958.86 ms     1970.03 ms
100% modules edited                        0.147     6779.83 ms     ±0.65%     6779.83 ms     6811.00 ms

Comparison: 
no module changes                       17733.43
1 module added                          10980.55 - 1.61x slower +0.0347 ms
1 module removed                           91.52 - 193.76x slower +10.87 ms
1 module edited                            82.97 - 213.73x slower +12.00 ms
1 added, 1 removed, 1 edited               78.18 - 226.82x slower +12.73 ms
3 added, 3 removed, 3 edited               44.10 - 402.10x slower +22.62 ms
10 added, 10 removed, 10 edited            18.58 - 954.58x slower +53.77 ms
1% added, 1% removed, 1% edited             9.25 - 1916.86x slower +108.04 ms
100% modules added                          5.31 - 3342.33x slower +188.42 ms
100% modules removed                        0.52 - 33995.56x slower +1916.98 ms
33% added, 33% removed, 34% edited          0.51 - 34656.31x slower +1954.24 ms
100% modules edited                        0.147 - 120229.58x slower +6779.77 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1         73.80       13.55 ms     ±2.07%       13.42 ms       14.40 ms
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2         19.13       52.27 ms     ±3.52%       51.82 ms       63.21 ms
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
1 vertex          39.83 K       25.10 μs   ±120.06%       22.73 μs      194.09 μs
2 vertices        35.25 K       28.37 μs   ±114.93%       26.92 μs       54.81 μs
4 vertices        29.82 K       33.54 μs    ±24.33%       33.25 μs       67.55 μs
8 vertices        19.52 K       51.23 μs    ±16.54%       51.13 μs       81.53 μs
16 vertices       10.44 K       95.80 μs    ±11.33%       94.75 μs      123.90 μs
32 vertices        3.24 K      308.58 μs    ±27.35%      294.75 μs      400.79 μs

Comparison: 
1 vertex          39.83 K
2 vertices        35.25 K - 1.13x slower +3.26 μs
4 vertices        29.82 K - 1.34x slower +8.43 μs
8 vertices        19.52 K - 2.04x slower +26.13 μs
16 vertices       10.44 K - 3.82x slower +70.69 μs
32 vertices        3.24 K - 12.29x slower +283.48 μs
```


### ✅ compiler » call_graph » server_callback_analysis_by_templatable_3

```
Name                                                ips        average  deviation         median         99th %
server_callback_analysis_by_templatable/3        8.67 K      115.31 μs   ±132.71%      105.04 μs      240.41 μs
```


### ✅ compiler » create_page_entry_files_6

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/6          5.01      199.73 ms     ±5.64%      199.33 ms      219.27 ms
```


### ✅ compiler » create_runtime_entry_file_7

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/7          8.68      115.26 ms     ±4.40%      114.32 ms      142.16 ms
```


### ✅ compiler » diff_module_info_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                     1532.49        0.65 ms     ±4.04%        0.65 ms        0.74 ms
100% modules added                       1359.06        0.74 ms     ±2.62%        0.73 ms        0.79 ms
33% added, 33% removed, 34% edited        918.95        1.09 ms    ±26.79%        1.15 ms        1.59 ms
1% added, 1% removed, 1% edited           688.64        1.45 ms     ±1.61%        1.45 ms        1.52 ms
1 module edited                           687.58        1.45 ms     ±2.81%        1.45 ms        1.62 ms
10 added, 10 removed, 10 edited           687.54        1.45 ms     ±2.38%        1.45 ms        1.56 ms
1 module added                            687.53        1.45 ms     ±3.04%        1.45 ms        1.64 ms
1 added, 1 removed, 1 edited              683.78        1.46 ms     ±3.87%        1.45 ms        1.77 ms
no module changes                         681.88        1.47 ms     ±5.09%        1.45 ms        1.83 ms
3 added, 3 removed, 3 edited              677.59        1.48 ms     ±5.01%        1.45 ms        1.84 ms
1 module removed                          664.84        1.50 ms     ±5.65%        1.48 ms        1.86 ms
100% modules edited                       663.85        1.51 ms     ±6.75%        1.47 ms        1.96 ms

Comparison: 
100% modules removed                     1532.49
100% modules added                       1359.06 - 1.13x slower +0.0833 ms
33% added, 33% removed, 34% edited        918.95 - 1.67x slower +0.44 ms
1% added, 1% removed, 1% edited           688.64 - 2.23x slower +0.80 ms
1 module edited                           687.58 - 2.23x slower +0.80 ms
10 added, 10 removed, 10 edited           687.54 - 2.23x slower +0.80 ms
1 module added                            687.53 - 2.23x slower +0.80 ms
1 added, 1 removed, 1 edited              683.78 - 2.24x slower +0.81 ms
no module changes                         681.88 - 2.25x slower +0.81 ms
3 added, 3 removed, 3 edited              677.59 - 2.26x slower +0.82 ms
1 module removed                          664.84 - 2.31x slower +0.85 ms
100% modules edited                       663.85 - 2.31x slower +0.85 ms
```


### ✅ compiler » encode_reachable_functions_5

```
Name                                   ips        average  deviation         median         99th %
encode_reachable_functions/5         50.59       19.77 ms     ±6.44%       19.53 ms       24.89 ms
```


### ✅ compiler » encoder » encode_term!_1

```
Name                                     ips        average  deviation         median         99th %
10 KB of text                       12272.69      0.0815 ms    ±11.11%      0.0769 ms       0.109 ms
200 KB binary that is not text       2656.65        0.38 ms     ±8.84%        0.36 ms        0.47 ms
80 KB of text                        1524.40        0.66 ms     ±2.12%        0.65 ms        0.71 ms
256 KB of non-ASCII text              680.95        1.47 ms     ±0.85%        1.47 ms        1.51 ms
160 KB of text                        610.33        1.64 ms    ±28.48%        1.62 ms        1.77 ms
320 KB of text                        323.23        3.09 ms     ±1.00%        3.09 ms        3.18 ms
640 KB of text                        144.64        6.91 ms     ±2.55%        6.93 ms        7.39 ms

Comparison: 
10 KB of text                       12272.69
200 KB binary that is not text       2656.65 - 4.62x slower +0.29 ms
80 KB of text                        1524.40 - 8.05x slower +0.57 ms
256 KB of non-ASCII text              680.95 - 18.02x slower +1.39 ms
160 KB of text                        610.33 - 20.11x slower +1.56 ms
320 KB of text                        323.23 - 37.97x slower +3.01 ms
640 KB of text                        144.64 - 84.85x slower +6.83 ms
```


### ✅ compiler » extract_component_queries_3

```
Name                                  ips        average  deviation         median         99th %
extract_component_queries/3       11.32 K       88.33 μs     ±9.96%       87.79 μs      108.63 μs
```


### ✅ compiler » list_reach_by_page_2

```
Name                           ips        average  deviation         median         99th %
list_reach_by_page/2         25.76       38.81 ms     ±6.52%       39.21 ms       50.95 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        6.66 K      0.00015 s    ±63.81%      0.00014 s      0.00022 s
do install     0.00014 K         7.21 s     ±3.19%         7.21 s         7.38 s

Comparison: 
no install        6.66 K
do install     0.00014 K - 48050.93x slower +7.21 s
```


### ✅ compiler » maybe_load_module_info_plt_1

```
Name              ips        average  deviation         median         99th %
no load       71.88 K      0.0139 ms    ±45.46%      0.0134 ms      0.0237 ms
do load        0.22 K        4.54 ms     ±7.61%        4.49 ms        5.25 ms

Comparison: 
no load       71.88 K
do load        0.22 K - 326.65x slower +4.53 ms
```


### ✅ compiler » query_extractor » extract_module_queries_3

```
Name                                                         ips        average  deviation         median         99th %
no parameterized captures                              2836.72 K        0.35 μs  ±2357.77%        0.29 μs        0.50 μs
capture naming its entity                               127.92 K        7.82 μs   ±171.30%        7.33 μs       22.08 μs
capture whose entity is an argument, 1 candidate        103.48 K        9.66 μs    ±62.75%        9.08 μs       22.13 μs
capture whose entity is an argument, 21 candidates       14.26 K       70.12 μs     ±9.37%       71.54 μs       87.04 μs

Comparison: 
no parameterized captures                              2836.72 K
capture naming its entity                               127.92 K - 22.18x slower +7.46 μs
capture whose entity is an argument, 1 candidate        103.48 K - 27.41x slower +9.31 μs
capture whose entity is an argument, 21 candidates       14.26 K - 198.91x slower +69.77 μs
```


### ✅ compiler » validate_operations!_4

```
Name                      ips        average  deviation         median         99th %
one edited page        161.27        6.20 ms     ±1.66%        6.15 ms        6.45 ms
every caller           154.19        6.49 ms     ±6.27%        6.40 ms        7.11 ms

Comparison: 
one edited page        161.27
every caller           154.19 - 1.05x slower +0.29 ms
```


### ✅ compiler » validate_page_modules_2

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/2       55.47 K       18.03 μs    ±37.66%       17.21 μs       36.88 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                                            ips        average  deviation         median         99th %
nothing changed, Hologram off               1630.68        0.61 ms    ±17.30%        0.58 ms        1.11 ms
nothing changed, new VM                      106.00        9.43 ms     ±5.02%        9.26 ms       11.20 ms
a module changed, Hologram off                26.23       38.13 ms    ±18.58%       35.24 ms       63.59 ms
a module no page uses edited, same VM         13.16       75.98 ms     ±6.38%       75.22 ms      111.53 ms
nothing changed, same VM                      12.90       77.51 ms     ±6.04%       75.85 ms       99.62 ms
one page edited, same VM                       3.52      284.13 ms     ±1.91%      283.39 ms      304.71 ms
cold                                           0.39     2592.58 ms     ±1.20%     2589.86 ms     2631.87 ms

Comparison: 
nothing changed, Hologram off               1630.68
nothing changed, new VM                      106.00 - 15.38x slower +8.82 ms
a module changed, Hologram off                26.23 - 62.17x slower +37.51 ms
a module no page uses edited, same VM         13.16 - 123.89x slower +75.36 ms
nothing changed, same VM                      12.90 - 126.39x slower +76.90 ms
one page edited, same VM                       3.52 - 463.32x slower +283.51 ms
cold                                           0.39 - 4227.67x slower +2591.97 ms
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           143.59 M        6.96 ns  ±4875.60%        8.30 ns        8.40 ns
is atom                10.21 M       97.94 ns  ±9981.77%          42 ns          84 ns
is Erlang module       10.18 M       98.19 ns  ±9780.08%          42 ns          84 ns
is Elixir module      0.0111 M    89838.99 ns    ±99.08%       83625 ns   154416.31 ns

Comparison: 
is not atom           143.59 M
is atom                10.21 M - 14.06x slower +90.98 ns
is Erlang module       10.18 M - 14.10x slower +91.23 ns
is Elixir module      0.0111 M - 12900.35x slower +89832.02 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           138.11 M     0.00724 μs  ±4812.54%     0.00830 μs     0.00840 μs
is Erlang module        2.21 M        0.45 μs  ±1032.02%        0.42 μs        0.46 μs
is atom               0.0626 M       15.96 μs    ±32.44%       15.75 μs       20.96 μs
is Elixir module     0.00866 M      115.49 μs    ±34.91%      104.75 μs      231.24 μs

Comparison: 
is not atom           138.11 M
is Erlang module        2.21 M - 62.37x slower +0.44 μs
is atom               0.0626 M - 2204.82x slower +15.96 μs
is Elixir module     0.00866 M - 15951.03x slower +115.48 μs
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3        3.76 M      265.81 ns  ±3220.77%         208 ns         250 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1        3.31 K      302.29 μs    ±27.58%      289.54 μs      455.19 μs
```


### ✅ reflection » list_components_0

```
Name                        ips        average  deviation         median         99th %
list_components/0         10.66       93.78 ms     ±4.30%       92.73 ms      117.24 ms
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         10.78       92.78 ms     ±3.06%       92.22 ms      114.01 ms
```


### ✅ reflection » list_entities_0

```
Name                      ips        average  deviation         median         99th %
list_entities/0          2.32      431.44 ms     ±3.90%      422.19 ms      479.38 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         10.68       93.60 ms     ±3.60%       93.03 ms      114.03 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           143.77 M     0.00696 μs  ±4875.63%     0.00830 μs     0.00840 μs
is Erlang module        4.04 M        0.25 μs  ±2754.98%        0.21 μs        0.38 μs
is atom               0.0636 M       15.71 μs    ±39.24%       15.50 μs       20.46 μs
is Elixir module      0.0562 M       17.79 μs    ±67.65%       15.33 μs       34.79 μs

Comparison: 
is not atom           143.77 M
is Erlang module        4.04 M - 35.59x slower +0.24 μs
is atom               0.0636 M - 2259.18x slower +15.71 μs
is Elixir module      0.0562 M - 2557.52x slower +17.78 μs
```

