# Elixir Benchmarks

Last run: 2026-07-05 11:29:48 UTC

## Summary

Total benchmarks: 34

Successful: 34\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.54      393.93 ms     ±3.22%      390.90 ms      420.89 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          3.86      259.15 ms     ±8.54%      257.50 ms      337.47 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          2.11      473.87 ms     ±1.43%      471.78 ms      490.38 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          4.11      243.05 ms     ±3.98%      244.90 ms      260.85 ms
```


### ✅ compiler » build_page_js_6

```
Name                      ips        average  deviation         median         99th %
build_page_js/6         70.82       14.12 ms    ±14.38%       14.67 ms       17.32 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          4.59      218.01 ms     ±1.91%      217.77 ms      233.56 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         46.76       21.38 ms    ±15.40%       19.13 ms       26.67 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                21.96       45.53 ms     ±4.70%       44.92 ms       58.26 ms
dump dir exists, dump file doesn't exist         21.84       45.78 ms     ±3.01%       45.60 ms       55.75 ms
dump dir doesn't exists                          21.80       45.88 ms     ±4.55%       45.38 ms       60.87 ms

Comparison: 
dump dir exists, dump file exists                21.96
dump dir exists, dump file doesn't exist         21.84 - 1.01x slower +0.25 ms
dump dir doesn't exists                          21.80 - 1.01x slower +0.34 ms
```


### ✅ compiler » call_graph » list_page_mfas_3

```
Name                       ips        average  deviation         median         99th %
list_page_mfas/3         69.52       14.38 ms    ±22.22%       12.88 ms       20.19 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_2

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/2         29.27       34.16 ms     ±8.20%       32.56 ms       40.07 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      134873.72     0.00741 ms    ±15.69%     0.00717 ms      0.0110 ms
1 module added                           2228.84        0.45 ms     ±6.57%        0.44 ms        0.53 ms
1 module removed                           64.72       15.45 ms    ±26.78%       16.61 ms       19.30 ms
1 added, 1 removed, 1 edited               60.94       16.41 ms    ±24.42%       17.64 ms       21.32 ms
1 module edited                            59.26       16.88 ms    ±23.42%       17.88 ms       21.07 ms
3 added, 3 removed, 3 edited               39.26       25.47 ms    ±12.74%       25.84 ms       30.60 ms
10 added, 10 removed, 10 edited            19.88       50.31 ms    ±16.17%       49.37 ms       87.29 ms
1% added, 1% removed, 1% edited            12.83       77.92 ms     ±7.12%       79.42 ms       89.02 ms
100% modules added                          4.18      239.34 ms     ±4.37%      240.10 ms      269.94 ms
100% modules removed                        0.70     1431.30 ms     ±0.71%     1433.59 ms     1443.93 ms
33% added, 33% removed, 34% edited          0.62     1608.84 ms     ±3.50%     1616.60 ms     1675.54 ms
100% modules edited                         0.24     4118.13 ms     ±2.54%     4159.59 ms     4195.52 ms

Comparison: 
no module changes                      134873.72
1 module added                           2228.84 - 60.51x slower +0.44 ms
1 module removed                           64.72 - 2083.95x slower +15.44 ms
1 added, 1 removed, 1 edited               60.94 - 2213.26x slower +16.40 ms
1 module edited                            59.26 - 2276.14x slower +16.87 ms
3 added, 3 removed, 3 edited               39.26 - 3435.16x slower +25.46 ms
10 added, 10 removed, 10 edited            19.88 - 6785.82x slower +50.31 ms
1% added, 1% removed, 1% edited            12.83 - 10509.10x slower +77.91 ms
100% modules added                          4.18 - 32280.21x slower +239.33 ms
100% modules removed                        0.70 - 193044.97x slower +1431.29 ms
33% added, 33% removed, 34% edited          0.62 - 216989.93x slower +1608.83 ms
100% modules edited                         0.24 - 555427.27x slower +4118.12 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1         31.92       31.33 ms     ±1.32%       31.22 ms       32.15 ms
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       73.88 K       13.54 μs     ±8.92%       13.33 μs       20.29 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
2 vertices      1153.16 K        0.87 μs    ±47.37%        0.71 μs        2.77 μs
1 vertex        1035.38 K        0.97 μs    ±45.55%        0.83 μs        2.63 μs
4 vertices       856.69 K        1.17 μs    ±38.94%        1.04 μs        2.86 μs
8 vertices       722.18 K        1.38 μs    ±66.46%        1.21 μs        3.17 μs
16 vertices      621.99 K        1.61 μs    ±26.78%        1.50 μs        3.48 μs
32 vertices      403.09 K        2.48 μs    ±17.96%        2.33 μs        4.49 μs

Comparison: 
2 vertices      1153.16 K
1 vertex        1035.38 K - 1.11x slower +0.0986 μs
4 vertices       856.69 K - 1.35x slower +0.30 μs
8 vertices       722.18 K - 1.60x slower +0.52 μs
16 vertices      621.99 K - 1.85x slower +0.74 μs
32 vertices      403.09 K - 2.86x slower +1.61 μs
```


### ✅ compiler » call_graph » server_callback_analysis_by_templatable_2

```
Name                                                ips        average  deviation         median         99th %
server_callback_analysis_by_templatable/2        7.59 K      131.78 μs    ±12.63%      129.33 μs      158.87 μs
```


### ✅ compiler » call_graph » server_protocol_dispatch_types_2

```
Name                       ips        average  deviation         median         99th %
1 templatable           4.27 K      234.04 μs    ±13.34%      230.25 μs      292.67 μs
all templatables        3.53 K      283.01 μs    ±14.04%      277.25 μs      354.29 μs

Comparison: 
1 templatable           4.27 K
all templatables        3.53 K - 1.21x slower +48.96 μs
```


### ✅ compiler » create_page_entry_files_5

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/5          1.05      949.73 ms     ±2.89%      941.21 ms     1014.11 ms
```


### ✅ compiler » create_runtime_entry_file_4

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/4         26.28       38.05 ms    ±10.77%       37.67 ms       51.59 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.38 K      228.42 μs     ±4.93%      226.46 μs      260.13 μs
100% modules added                        3.45 K      289.46 μs    ±39.02%      268.33 μs      443.12 μs
33% added, 33% removed, 34% edited        2.65 K      377.79 μs     ±8.42%      373.96 μs      488.15 μs
10 added, 10 removed, 10 edited           1.71 K      584.17 μs     ±3.88%      579.66 μs      670.54 μs
no module changes                         1.70 K      588.18 μs     ±3.17%      585.55 μs      649.35 μs
3 added, 3 removed, 3 edited              1.69 K      593.18 μs     ±4.06%      590.17 μs      680.46 μs
100% modules edited                       1.67 K      597.66 μs     ±8.51%      582.17 μs      758.03 μs
1% added, 1% removed, 1% edited           1.66 K      602.28 μs     ±6.15%      585.92 μs      725.35 μs
1 added, 1 removed, 1 edited              1.62 K      618.24 μs    ±12.12%      611.63 μs      794.26 μs
1 module added                            1.62 K      618.56 μs     ±6.44%      609.21 μs      751.41 μs
1 module edited                           1.60 K      625.70 μs    ±19.66%      615.75 μs      743.88 μs
1 module removed                          1.59 K      627.23 μs     ±7.44%      618.17 μs      780.64 μs

Comparison: 
100% modules removed                      4.38 K
100% modules added                        3.45 K - 1.27x slower +61.05 μs
33% added, 33% removed, 34% edited        2.65 K - 1.65x slower +149.37 μs
10 added, 10 removed, 10 edited           1.71 K - 2.56x slower +355.76 μs
no module changes                         1.70 K - 2.58x slower +359.76 μs
3 added, 3 removed, 3 edited              1.69 K - 2.60x slower +364.76 μs
100% modules edited                       1.67 K - 2.62x slower +369.25 μs
1% added, 1% removed, 1% edited           1.66 K - 2.64x slower +373.86 μs
1 added, 1 removed, 1 edited              1.62 K - 2.71x slower +389.82 μs
1 module added                            1.62 K - 2.71x slower +390.14 μs
1 module edited                           1.60 K - 2.74x slower +397.28 μs
1 module removed                          1.59 K - 2.75x slower +398.82 μs
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        8.11 K      0.00012 s    ±22.19%      0.00013 s      0.00021 s
do install     0.00011 K         9.40 s    ±12.37%         9.40 s        10.22 s

Comparison: 
no install        8.11 K
do install     0.00011 K - 76151.71x slower +9.40 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      178.71 K     0.00560 ms   ±469.89%     0.00483 ms      0.0138 ms
do load      0.0119 K       83.75 ms     ±2.20%       83.81 ms       89.06 ms

Comparison: 
no load      178.71 K
do load      0.0119 K - 14967.81x slower +83.75 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      108.48 K     0.00922 ms    ±61.68%     0.00879 ms      0.0155 ms
do load     0.00189 K      529.68 ms     ±2.43%      523.88 ms      559.45 ms

Comparison: 
no load      108.48 K
do load     0.00189 K - 57460.24x slower +529.67 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      106.22 K        9.41 μs    ±65.54%        8.96 μs       16.17 μs
do load        2.04 K      490.99 μs     ±8.28%      484.08 μs      673.91 μs

Comparison: 
no load      106.22 K
do load        2.04 K - 52.15x slower +481.57 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      120.03 K        8.33 μs    ±76.52%        8.25 μs        9.04 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache       40.40 K       24.76 μs    ±59.81%       20.25 μs       87.83 μs
no cache        29.13 K       34.33 μs    ±28.31%       31.63 μs       60.15 μs

Comparison: 
has cache       40.40 K
no cache        29.13 K - 1.39x slower +9.58 μs
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           167.43 M        5.97 ns  ±5481.69%        4.20 ns        8.40 ns
is atom                12.26 M       81.57 ns  ±9576.14%          42 ns          84 ns
is Erlang module       11.97 M       83.52 ns  ±9762.90%          42 ns          84 ns
is Elixir module        9.23 M      108.37 ns  ±6252.78%          83 ns         125 ns

Comparison: 
is not atom           167.43 M
is atom                12.26 M - 13.66x slower +75.60 ns
is Erlang module       11.97 M - 13.98x slower +77.55 ns
is Elixir module        9.23 M - 18.14x slower +102.40 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           161.16 M        6.21 ns  ±4643.90%        4.20 ns        8.40 ns
is Elixir module       16.45 M       60.80 ns  ±6920.87%          42 ns          84 ns
is Erlang module       15.65 M       63.89 ns  ±6310.69%          42 ns          84 ns
is atom               0.0721 M    13861.22 ns    ±51.99%       13166 ns       21209 ns

Comparison: 
is not atom           161.16 M
is Elixir module       16.45 M - 9.80x slower +54.60 ns
is Erlang module       15.65 M - 10.30x slower +57.68 ns
is atom               0.0721 M - 2233.84x slower +13855.02 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.48 M       64.60 ns  ±9222.34%          42 ns          84 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.50 M       79.99 ns  ±5484.05%          83 ns          84 ns
```


### ✅ reflection » list_components_0

```
Name                        ips        average  deviation         median         99th %
list_components/0         52.34       19.10 ms     ±6.92%       19.23 ms       21.79 ms
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         52.85       18.92 ms     ±6.79%       18.75 ms       21.74 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         52.73       18.96 ms     ±7.65%       18.37 ms       21.73 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        238.67        4.19 ms     ±5.38%        4.13 ms        5.09 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            27.55 M       36.30 ns    ±63.54%          42 ns          42 ns
is Elixir module       22.08 M       45.29 ns  ±1827.01%          42 ns          42 ns
is Erlang module       22.02 M       45.41 ns  ±1833.99%          42 ns          42 ns
is atom               0.0751 M    13315.43 ns    ±52.14%       12750 ns       20291 ns

Comparison: 
is not atom            27.55 M
is Elixir module       22.08 M - 1.25x slower +8.99 ns
is Erlang module       22.02 M - 1.25x slower +9.11 ns
is atom               0.0751 M - 366.84x slower +13279.13 ns
```

