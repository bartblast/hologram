# Elixir Benchmarks

Last run: 2026-10-11 20:38:34 UTC

## Summary

Total benchmarks: 40

Successful: 40\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          1.54      650.94 ms     ±3.30%      640.36 ms      703.46 ms
```


### ✅ compiler » build_app_versions_1

```
Name                           ips        average  deviation         median         99th %
build_app_versions/1         14.30       69.95 ms     ±5.75%       69.47 ms      102.49 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          1.40      714.01 ms     ±4.35%      715.84 ms      749.40 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          1.39      719.99 ms     ±1.77%      715.28 ms      745.42 ms
```


### ✅ compiler » build_missing_ir!_2

```
Name                      ips        average  deviation         median         99th %
nothing missing        7.74 K       0.129 ms    ±21.21%       0.126 ms       0.172 ms
all missing         0.00160 K      626.00 ms     ±1.19%      627.45 ms      637.40 ms

Comparison: 
nothing missing        7.74 K
all missing         0.00160 K - 4842.92x slower +625.87 ms
```


### ✅ compiler » build_module_info_plt!_2

```
Name                                                          ips        average  deviation         median         99th %
previous dump, nothing changed (every entry reused)          9.53      104.89 ms     ±6.49%      103.28 ms      129.87 ms
no previous dump (every beam read)                           5.29      189.04 ms     ±3.63%      187.30 ms      211.66 ms

Comparison: 
previous dump, nothing changed (every entry reused)          9.53
no previous dump (every beam read)                           5.29 - 1.80x slower +84.15 ms
```


### ✅ compiler » build_module_metadata_1

```
Name                              ips        average  deviation         median         99th %
build_module_metadata/1        375.20        2.67 ms    ±12.48%        2.60 ms        3.54 ms
```


### ✅ compiler » build_page_js_5

```
Name                      ips        average  deviation         median         99th %
build_page_js/5        223.89        4.47 ms    ±14.68%        4.37 ms        5.51 ms
```


### ✅ compiler » build_queries_2

```
Name                      ips        average  deviation         median         99th %
build_queries/2          2.29      436.90 ms     ±5.34%      433.04 ms      499.56 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          2.79      358.23 ms     ±2.28%      358.25 ms      378.80 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         31.60       31.64 ms    ±14.95%       28.49 ms       39.50 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                14.23       70.30 ms     ±7.40%       69.03 ms      107.97 ms
dump dir exists, dump file doesn't exist         14.13       70.76 ms     ±6.78%       69.25 ms       97.10 ms
dump dir doesn't exists                          13.67       73.15 ms    ±11.52%       70.82 ms      129.93 ms

Comparison: 
dump dir exists, dump file exists                14.23
dump dir exists, dump file doesn't exist         14.13 - 1.01x slower +0.47 ms
dump dir doesn't exists                          13.67 - 1.04x slower +2.86 ms
```


### ✅ compiler » call_graph » list_modules_reaching_2

```
Name                    ips        average  deviation         median         99th %
1 leaf module        996.87        1.00 ms   ±157.26%        0.90 ms        1.77 ms
1 core module        858.02        1.17 ms     ±9.39%        1.13 ms        1.44 ms
10 modules            10.33       96.76 ms     ±5.12%       95.59 ms      123.52 ms

Comparison: 
1 leaf module        996.87
1 core module        858.02 - 1.16x slower +0.162 ms
10 modules            10.33 - 96.46x slower +95.76 ms
```


### ✅ compiler » call_graph » list_page_mfas_4

```
Name                       ips        average  deviation         median         99th %
list_page_mfas/4        591.13        1.69 ms    ±16.11%        1.63 ms        2.20 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1        305.80        3.27 ms    ±11.53%        3.14 ms        4.45 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                       20558.38      0.0486 ms     ±9.98%      0.0482 ms      0.0577 ms
1 module added                           9879.06       0.101 ms    ±13.41%      0.0991 ms       0.138 ms
1 added, 1 removed, 1 edited               81.91       12.21 ms    ±61.44%        8.83 ms       30.53 ms
1 module removed                           73.68       13.57 ms    ±76.64%       21.00 ms       27.53 ms
1 module edited                            72.63       13.77 ms    ±69.13%        6.91 ms       27.97 ms
3 added, 3 removed, 3 edited               45.95       21.76 ms    ±41.72%       16.31 ms       37.68 ms
10 added, 10 removed, 10 edited            20.12       49.70 ms    ±15.54%       45.84 ms       63.81 ms
1% added, 1% removed, 1% edited             9.31      107.46 ms     ±8.29%      113.25 ms      118.75 ms
100% modules added                          5.43      184.12 ms     ±2.35%      184.90 ms      190.18 ms
100% modules removed                        0.55     1816.88 ms     ±0.44%     1819.16 ms     1826.65 ms
33% added, 33% removed, 34% edited          0.54     1850.81 ms     ±1.19%     1858.41 ms     1871.17 ms
100% modules edited                        0.153     6531.56 ms     ±0.60%     6531.56 ms     6559.25 ms

Comparison: 
no module changes                       20558.38
1 module added                           9879.06 - 2.08x slower +0.0526 ms
1 added, 1 removed, 1 edited               81.91 - 250.98x slower +12.16 ms
1 module removed                           73.68 - 279.02x slower +13.52 ms
1 module edited                            72.63 - 283.07x slower +13.72 ms
3 added, 3 removed, 3 edited               45.95 - 447.43x slower +21.72 ms
10 added, 10 removed, 10 edited            20.12 - 1021.75x slower +49.65 ms
1% added, 1% removed, 1% edited             9.31 - 2209.10x slower +107.41 ms
100% modules added                          5.43 - 3785.16x slower +184.07 ms
100% modules removed                        0.55 - 37352.06x slower +1816.83 ms
33% added, 33% removed, 34% edited          0.54 - 38049.63x slower +1850.76 ms
100% modules edited                        0.153 - 134278.24x slower +6531.51 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1         22.33       44.77 ms     ±1.80%       44.68 ms       47.07 ms
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       43.24 K       23.13 μs    ±15.97%       22.63 μs       48.29 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
4 vertices       856.51 K        1.17 μs    ±50.08%        1.04 μs        3.53 μs
8 vertices       637.18 K        1.57 μs    ±53.10%        1.33 μs        4.30 μs
2 vertices       518.57 K        1.93 μs    ±72.49%        1.54 μs        5.32 μs
1 vertex         429.08 K        2.33 μs    ±50.50%        2.46 μs        5.83 μs
16 vertices      380.17 K        2.63 μs    ±39.17%        2.38 μs        5.65 μs
32 vertices      337.34 K        2.96 μs    ±24.57%        2.83 μs        5.67 μs

Comparison: 
4 vertices       856.51 K
8 vertices       637.18 K - 1.34x slower +0.40 μs
2 vertices       518.57 K - 1.65x slower +0.76 μs
1 vertex         429.08 K - 2.00x slower +1.16 μs
16 vertices      380.17 K - 2.25x slower +1.46 μs
32 vertices      337.34 K - 2.54x slower +1.80 μs
```


### ✅ compiler » call_graph » server_callback_analysis_by_templatable_3

```
Name                                                ips        average  deviation         median         99th %
server_callback_analysis_by_templatable/3        9.48 K      105.53 μs    ±25.81%      100.38 μs      154.40 μs
```


### ✅ compiler » create_page_entry_files_6

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/6          5.18      192.98 ms     ±4.61%      191.28 ms      226.75 ms
```


### ✅ compiler » create_runtime_entry_file_7

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/7          8.85      112.95 ms     ±4.02%      112.14 ms      131.22 ms
```


### ✅ compiler » diff_module_info_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                     1532.24        0.65 ms    ±16.55%        0.64 ms        0.90 ms
100% modules added                       1363.57        0.73 ms    ±11.80%        0.72 ms        0.99 ms
33% added, 33% removed, 34% edited        939.69        1.06 ms    ±24.44%        1.13 ms        1.49 ms
1 module added                            693.29        1.44 ms     ±2.84%        1.44 ms        1.55 ms
3 added, 3 removed, 3 edited              692.18        1.44 ms     ±2.06%        1.44 ms        1.55 ms
no module changes                         691.66        1.45 ms     ±1.92%        1.44 ms        1.54 ms
100% modules edited                       687.67        1.45 ms     ±3.03%        1.44 ms        1.62 ms
10 added, 10 removed, 10 edited           673.41        1.48 ms    ±12.98%        1.44 ms        2.01 ms
1% added, 1% removed, 1% edited           673.02        1.49 ms    ±12.88%        1.44 ms        2.01 ms
1 added, 1 removed, 1 edited              671.22        1.49 ms     ±8.89%        1.44 ms        1.99 ms
1 module removed                          668.68        1.50 ms    ±13.29%        1.45 ms        2.02 ms
1 module edited                           665.11        1.50 ms    ±12.53%        1.45 ms        2.03 ms

Comparison: 
100% modules removed                     1532.24
100% modules added                       1363.57 - 1.12x slower +0.0807 ms
33% added, 33% removed, 34% edited        939.69 - 1.63x slower +0.41 ms
1 module added                            693.29 - 2.21x slower +0.79 ms
3 added, 3 removed, 3 edited              692.18 - 2.21x slower +0.79 ms
no module changes                         691.66 - 2.22x slower +0.79 ms
100% modules edited                       687.67 - 2.23x slower +0.80 ms
10 added, 10 removed, 10 edited           673.41 - 2.28x slower +0.83 ms
1% added, 1% removed, 1% edited           673.02 - 2.28x slower +0.83 ms
1 added, 1 removed, 1 edited              671.22 - 2.28x slower +0.84 ms
1 module removed                          668.68 - 2.29x slower +0.84 ms
1 module edited                           665.11 - 2.30x slower +0.85 ms
```


### ✅ compiler » encode_reachable_functions_5

```
Name                                   ips        average  deviation         median         99th %
encode_reachable_functions/5         53.93       18.54 ms     ±5.55%       18.61 ms       20.99 ms
```


### ✅ compiler » encoder » encode_term!_1

```
Name                                     ips        average  deviation         median         99th %
10 KB of text                       12432.00      0.0804 ms    ±11.95%      0.0743 ms       0.107 ms
200 KB binary that is not text       2778.44        0.36 ms     ±2.16%        0.36 ms        0.39 ms
80 KB of text                        1527.37        0.65 ms     ±1.76%        0.65 ms        0.71 ms
256 KB of non-ASCII text              680.57        1.47 ms     ±0.87%        1.47 ms        1.52 ms
160 KB of text                        621.81        1.61 ms     ±2.32%        1.60 ms        1.74 ms
320 KB of text                        323.91        3.09 ms     ±1.05%        3.09 ms        3.19 ms
640 KB of text                        147.96        6.76 ms     ±2.26%        6.79 ms        7.06 ms

Comparison: 
10 KB of text                       12432.00
200 KB binary that is not text       2778.44 - 4.47x slower +0.28 ms
80 KB of text                        1527.37 - 8.14x slower +0.57 ms
256 KB of non-ASCII text              680.57 - 18.27x slower +1.39 ms
160 KB of text                        621.81 - 19.99x slower +1.53 ms
320 KB of text                        323.91 - 38.38x slower +3.01 ms
640 KB of text                        147.96 - 84.02x slower +6.68 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        6.65 K      0.00015 s    ±73.58%      0.00014 s      0.00022 s
do install     0.00009 K        10.96 s     ±0.00%        10.96 s        10.96 s

Comparison: 
no install        6.65 K
do install     0.00009 K - 72943.97x slower +10.96 s
```


### ✅ compiler » maybe_load_module_info_plt_1

```
Name              ips        average  deviation         median         99th %
no load       64.16 K      0.0156 ms   ±114.55%      0.0141 ms      0.0374 ms
do load        0.21 K        4.70 ms     ±7.37%        4.66 ms        5.36 ms

Comparison: 
no load       64.16 K
do load        0.21 K - 301.79x slower +4.69 ms
```


### ✅ compiler » query_extractor » extract_module_queries_2

```
Name                                                         ips        average  deviation         median         99th %
no parameterized captures                              2911.06 K        0.34 μs  ±1738.31%        0.29 μs        0.50 μs
capture naming its entity                                 6.98 K      143.23 μs    ±48.39%         142 μs      183.91 μs
capture whose entity is an argument, 1 candidate          6.92 K      144.54 μs     ±7.83%      143.88 μs      181.89 μs
capture whose entity is an argument, 21 candidates        4.72 K      211.83 μs     ±5.52%      209.04 μs      245.29 μs

Comparison: 
no parameterized captures                              2911.06 K
capture naming its entity                                 6.98 K - 416.96x slower +142.89 μs
capture whose entity is an argument, 1 candidate          6.92 K - 420.78x slower +144.20 μs
capture whose entity is an argument, 21 candidates        4.72 K - 616.65x slower +211.49 μs
```


### ✅ compiler » query_extractor » validate_slot_bindings!_1

```
Name                                ips        average  deviation         median         99th %
no parameterized captures        2.80 M        0.36 μs  ±1967.04%        0.29 μs        0.54 μs
parameterized capture         0.00735 M      136.10 μs    ±18.08%      129.79 μs      175.58 μs

Comparison: 
no parameterized captures        2.80 M
parameterized capture         0.00735 M - 381.09x slower +135.74 μs
```


### ✅ compiler » validate_page_modules_2

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/2       59.70 K       16.75 μs    ±84.72%       15.92 μs       37.88 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache          0.76         1.32 s     ±3.48%         1.31 s         1.39 s
no cache          0.104         9.62 s     ±0.00%         9.62 s         9.62 s

Comparison: 
has cache          0.76
no cache          0.104 - 7.27x slower +8.30 s
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            24.10 M       41.50 ns    ±28.96%          42 ns          42 ns
is Erlang module        9.54 M      104.87 ns  ±9285.86%          83 ns         125 ns
is atom                 9.51 M      105.12 ns  ±9543.23%          83 ns         125 ns
is Elixir module      0.0118 M    84757.06 ns    ±48.13%       82250 ns   140377.94 ns

Comparison: 
is not atom            24.10 M
is Erlang module        9.54 M - 2.53x slower +63.37 ns
is atom                 9.51 M - 2.53x slower +63.62 ns
is Elixir module      0.0118 M - 2042.35x slower +84715.56 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           141.47 M     0.00707 μs  ±4935.12%     0.00830 μs      0.0167 μs
is Erlang module        2.12 M        0.47 μs  ±1691.76%        0.42 μs        0.58 μs
is atom               0.0618 M       16.18 μs    ±41.73%       15.83 μs       27.08 μs
is Elixir module     0.00902 M      110.92 μs    ±38.11%      106.46 μs      181.93 μs

Comparison: 
is not atom           141.47 M
is Erlang module        2.12 M - 66.63x slower +0.46 μs
is atom               0.0618 M - 2288.98x slower +16.17 μs
is Elixir module     0.00902 M - 15691.39x slower +110.91 μs
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3        3.77 M      265.03 ns  ±3109.11%         209 ns         333 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1        3.33 K      300.71 μs    ±34.86%      289.38 μs      448.94 μs
```


### ✅ reflection » list_components_0

```
Name                        ips        average  deviation         median         99th %
list_components/0         11.42       87.54 ms     ±4.54%       86.89 ms      107.77 ms
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         10.88       91.88 ms     ±4.21%       91.06 ms      109.51 ms
```


### ✅ reflection » list_entities_0

```
Name                      ips        average  deviation         median         99th %
list_entities/0          2.28      438.13 ms     ±4.54%      428.25 ms      504.61 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         10.33       96.84 ms     ±5.51%       95.48 ms      124.12 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           137.84 M     0.00725 μs  ±4621.95%     0.00830 μs     0.00840 μs
is Erlang module        3.99 M        0.25 μs  ±2478.59%        0.21 μs        0.29 μs
is atom               0.0634 M       15.77 μs    ±44.02%       15.42 μs       22.38 μs
is Elixir module      0.0557 M       17.94 μs    ±61.81%       15.79 μs       38.38 μs

Comparison: 
is not atom           137.84 M
is Erlang module        3.99 M - 34.52x slower +0.24 μs
is atom               0.0634 M - 2174.21x slower +15.77 μs
is Elixir module      0.0557 M - 2472.92x slower +17.93 μs
```

