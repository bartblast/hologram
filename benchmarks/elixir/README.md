# Elixir Benchmarks

Last run: 2025-10-21 15:26:30.751127Z

## Summary

Total benchmarks: 31
Successful: 31
Warnings: 0
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.65      376.98 ms     ±2.90%      371.91 ms      405.66 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          1.59      628.72 ms     ±2.51%      626.63 ms      684.26 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          3.41      293.31 ms     ±1.06%      293.12 ms      300.27 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          5.23      191.19 ms     ±3.79%      190.65 ms      214.68 ms
```


### ✅ compiler » build_page_js_4

```
Name                      ips        average  deviation         median         99th %
build_page_js/4        116.81        8.56 ms    ±18.11%        9.37 ms       11.10 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          4.82      207.52 ms     ±2.88%      206.61 ms      221.46 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         51.14       19.55 ms    ±14.54%       17.98 ms       24.64 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file doesn't exist         24.07       41.54 ms     ±3.09%       41.42 ms       44.72 ms
dump dir doesn't exists                          23.99       41.68 ms     ±3.78%       41.36 ms       49.76 ms
dump dir exists, dump file exists                23.89       41.86 ms     ±3.42%       41.65 ms       48.46 ms

Comparison: 
dump dir exists, dump file doesn't exist         24.07
dump dir doesn't exists                          23.99 - 1.00x slower +0.146 ms
dump dir exists, dump file exists                23.89 - 1.01x slower +0.32 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         62.53       15.99 ms     ±3.11%       15.95 ms       17.33 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      209058.51     0.00478 ms    ±14.95%     0.00467 ms     0.00717 ms
1 module added                           1815.47        0.55 ms     ±3.17%        0.55 ms        0.58 ms
1 module removed                          717.97        1.39 ms     ±3.25%        1.37 ms        1.49 ms
1 module edited                           305.48        3.27 ms     ±5.46%        3.22 ms        3.78 ms
1 added, 1 removed, 1 edited              243.52        4.11 ms     ±4.00%        4.12 ms        4.55 ms
3 added, 3 removed, 3 edited               97.99       10.20 ms     ±4.01%       10.18 ms       11.19 ms
10 added, 10 removed, 10 edited            32.58       30.69 ms     ±2.39%       30.50 ms       32.07 ms
1% added, 1% removed, 1% edited            25.86       38.67 ms     ±1.43%       38.66 ms       39.97 ms
100% modules added                          2.02      494.65 ms     ±1.69%      492.47 ms      516.85 ms
33% added, 33% removed, 34% edited          0.89     1117.56 ms     ±1.44%     1120.99 ms     1137.41 ms
100% modules removed                        0.76     1311.28 ms     ±0.97%     1310.57 ms     1331.58 ms
100% modules edited                         0.32     3170.61 ms     ±0.72%     3173.72 ms     3191.81 ms

Comparison: 
no module changes                      209058.51
1 module added                           1815.47 - 115.15x slower +0.55 ms
1 module removed                          717.97 - 291.18x slower +1.39 ms
1 module edited                           305.48 - 684.36x slower +3.27 ms
1 added, 1 removed, 1 edited              243.52 - 858.48x slower +4.10 ms
3 added, 3 removed, 3 edited               97.99 - 2133.39x slower +10.20 ms
10 added, 10 removed, 10 edited            32.58 - 6416.25x slower +30.69 ms
1% added, 1% removed, 1% edited            25.86 - 8083.95x slower +38.66 ms
100% modules added                          2.02 - 103410.72x slower +494.64 ms
33% added, 33% removed, 34% edited          0.89 - 233635.76x slower +1117.56 ms
100% modules removed                        0.76 - 274135.06x slower +1311.28 ms
100% modules edited                         0.32 - 662842.20x slower +3170.60 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        593.92        1.68 ms     ±4.60%        1.65 ms        1.91 ms
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2         17.92       55.82 ms     ±2.66%       55.51 ms       60.85 ms
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
1 vertex          73.27 K       13.65 μs    ±34.93%       12.06 μs       27.39 μs
2 vertices        50.82 K       19.68 μs    ±29.12%       17.75 μs       33.33 μs
4 vertices        30.57 K       32.72 μs    ±19.23%       30.54 μs       47.92 μs
8 vertices        16.20 K       61.73 μs    ±27.32%       58.98 μs       81.42 μs
16 vertices       10.71 K       93.38 μs     ±9.65%       91.08 μs      114.41 μs
32 vertices        3.76 K      265.64 μs    ±12.93%         260 μs      322.24 μs

Comparison: 
1 vertex          73.27 K
2 vertices        50.82 K - 1.44x slower +6.03 μs
4 vertices        30.57 K - 2.40x slower +19.07 μs
8 vertices        16.20 K - 4.52x slower +48.08 μs
16 vertices       10.71 K - 6.84x slower +79.74 μs
32 vertices        3.76 K - 19.46x slower +251.99 μs
```


### ✅ compiler » create_page_entry_files_4

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/4          1.73      578.25 ms     ±0.98%      579.92 ms      590.62 ms
```


### ✅ compiler » create_runtime_entry_file_3

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/3         20.79       48.11 ms     ±7.91%       47.41 ms       65.13 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.68 K      213.60 μs     ±6.09%      213.83 μs      251.36 μs
100% modules added                        3.78 K      264.67 μs    ±10.66%      249.75 μs      362.52 μs
33% added, 33% removed, 34% edited        2.90 K      345.33 μs     ±8.36%      351.21 μs      436.09 μs
no module changes                         1.88 K      532.06 μs     ±4.19%      528.96 μs      611.64 μs
10 added, 10 removed, 10 edited           1.88 K      533.29 μs     ±3.01%      531.83 μs      596.99 μs
3 added, 3 removed, 3 edited              1.81 K      551.46 μs     ±3.58%      551.88 μs      618.73 μs
100% modules edited                       1.80 K      554.08 μs     ±5.18%      552.88 μs      679.33 μs
1 module edited                           1.78 K      561.44 μs     ±6.04%      549.67 μs      677.25 μs
1 added, 1 removed, 1 edited              1.76 K      569.38 μs     ±4.48%      563.58 μs      690.42 μs
1% added, 1% removed, 1% edited           1.75 K      572.24 μs    ±40.46%      551.96 μs      662.28 μs
1 module removed                          1.73 K      577.56 μs     ±8.44%      553.25 μs      714.96 μs
1 module added                            1.71 K      586.26 μs     ±7.51%      566.17 μs      702.00 μs

Comparison: 
100% modules removed                      4.68 K
100% modules added                        3.78 K - 1.24x slower +51.07 μs
33% added, 33% removed, 34% edited        2.90 K - 1.62x slower +131.73 μs
no module changes                         1.88 K - 2.49x slower +318.46 μs
10 added, 10 removed, 10 edited           1.88 K - 2.50x slower +319.69 μs
3 added, 3 removed, 3 edited              1.81 K - 2.58x slower +337.86 μs
100% modules edited                       1.80 K - 2.59x slower +340.48 μs
1 module edited                           1.78 K - 2.63x slower +347.84 μs
1 added, 1 removed, 1 edited              1.76 K - 2.67x slower +355.78 μs
1% added, 1% removed, 1% edited           1.75 K - 2.68x slower +358.64 μs
1 module removed                          1.73 K - 2.70x slower +363.96 μs
1 module added                            1.71 K - 2.74x slower +372.66 μs
```


### ✅ compiler » format_files_2

```
Name                     ips        average  deviation         median         99th %
format_files/2          1.19      837.49 ms     ±1.37%      837.53 ms      856.78 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install       14.70 K      0.00007 s    ±16.26%      0.00007 s      0.00011 s
do install     0.00011 K         9.33 s     ±0.00%         9.33 s         9.33 s

Comparison: 
no install       14.70 K
do install     0.00011 K - 137177.72x slower +9.33 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      211.74 K     0.00472 ms   ±122.10%     0.00458 ms     0.00638 ms
do load      0.0144 K       69.31 ms     ±1.25%       69.15 ms       74.03 ms

Comparison: 
no load      211.74 K
do load      0.0144 K - 14675.57x slower +69.31 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      106.81 K     0.00936 ms    ±68.69%     0.00904 ms      0.0137 ms
do load     0.00214 K      466.41 ms     ±2.03%      463.66 ms      488.39 ms

Comparison: 
no load      106.81 K
do load     0.00214 K - 49818.73x slower +466.40 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      107.24 K        9.32 μs    ±65.64%           9 μs       14.21 μs
do load        2.18 K      458.39 μs     ±3.88%      454.17 μs      530.67 μs

Comparison: 
no load      107.24 K
do load        2.18 K - 49.16x slower +449.06 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      162.44 K        6.16 μs   ±188.73%        6.08 μs        6.79 μs
```


### ✅ mix » tasks » compileroothologram

```
Name                ips        average  deviation         median         99th %
has cache          0.53         1.87 s     ±0.75%         1.87 s         1.90 s
no cache           0.21         4.87 s     ±0.83%         4.87 s         4.90 s

Comparison: 
has cache          0.53
no cache           0.21 - 2.61x slower +3.00 s
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           158.39 M        6.31 ns ±40503.82%        4.20 ns       16.60 ns
is Erlang module       10.05 M       99.52 ns ±50965.40%          42 ns          84 ns
is atom                 9.82 M      101.83 ns ±54464.89%          42 ns          84 ns
is Elixir module        7.80 M      128.26 ns ±39041.20%          83 ns         166 ns

Comparison: 
is not atom           158.39 M
is Erlang module       10.05 M - 15.76x slower +93.21 ns
is atom                 9.82 M - 16.13x slower +95.52 ns
is Elixir module        7.80 M - 20.32x slower +121.95 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           160.57 M        6.23 ns ±34792.67%        4.20 ns       16.60 ns
is Elixir module        8.96 M      111.66 ns ±33153.22%          83 ns         125 ns
is Erlang module        5.39 M      185.39 ns ±28561.94%          83 ns         166 ns
is atom               0.0369 M    27098.67 ns    ±47.69%       26833 ns       35833 ns

Comparison: 
is not atom           160.57 M
is Elixir module        8.96 M - 17.93x slower +105.43 ns
is Erlang module        5.39 M - 29.77x slower +179.16 ns
is atom               0.0369 M - 4351.14x slower +27092.44 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       14.20 M       70.42 ns ±53749.12%          42 ns          84 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.57 M       79.52 ns ±30869.45%          42 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         61.19       16.34 ms     ±9.65%       16.10 ms       19.68 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         56.25       17.78 ms     ±7.46%       18.02 ms       19.81 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        305.20        3.28 ms     ±4.51%        3.24 ms        3.78 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           156.22 M        6.40 ns ±31313.72%        4.20 ns       16.60 ns
is Elixir module       16.67 M       59.98 ns ±51806.42%          42 ns          42 ns
is Erlang module       16.65 M       60.06 ns ±51544.35%          42 ns          42 ns
is atom               0.0710 M    14093.78 ns   ±117.72%       12917 ns       25375 ns

Comparison: 
is not atom           156.22 M
is Elixir module       16.67 M - 9.37x slower +53.58 ns
is Erlang module       16.65 M - 9.38x slower +53.66 ns
is atom               0.0710 M - 2201.77x slower +14087.38 ns
```

