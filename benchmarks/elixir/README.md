# Elixir Benchmarks

Last run: 2026-07-04 11:37:20 UTC

## Summary

Total benchmarks: 30

Successful: 30\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.60      385.14 ms     ±4.47%      376.11 ms      433.83 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          4.08      245.15 ms     ±6.50%      241.12 ms      303.20 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          2.14      466.58 ms     ±1.15%      465.52 ms      478.81 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          4.30      232.66 ms     ±3.81%      232.27 ms      250.36 ms
```


### ✅ compiler » build_page_js_5

```
Name                      ips        average  deviation         median         99th %
build_page_js/5        104.02        9.61 ms    ±17.36%       10.93 ms       11.76 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          4.71      212.47 ms     ±3.36%      211.33 ms      240.36 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         46.51       21.50 ms    ±12.69%       19.76 ms       26.00 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                22.04       45.38 ms     ±5.96%       44.95 ms       67.85 ms
dump dir doesn't exists                          21.93       45.60 ms     ±6.56%       45.15 ms       68.75 ms
dump dir exists, dump file doesn't exist         21.76       45.95 ms     ±3.31%       45.71 ms       58.50 ms

Comparison: 
dump dir exists, dump file exists                22.04
dump dir doesn't exists                          21.93 - 1.00x slower +0.22 ms
dump dir exists, dump file doesn't exist         21.76 - 1.01x slower +0.57 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         62.88       15.90 ms    ±17.96%       14.43 ms       20.56 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      129032.75     0.00775 ms    ±20.30%     0.00729 ms      0.0153 ms
1 module added                           2311.25        0.43 ms     ±6.60%        0.43 ms        0.49 ms
1 module removed                           80.47       12.43 ms    ±25.31%       13.63 ms       16.05 ms
1 module edited                            74.77       13.37 ms    ±31.34%       14.89 ms       17.45 ms
1 added, 1 removed, 1 edited               67.03       14.92 ms    ±17.91%       15.01 ms       18.75 ms
3 added, 3 removed, 3 edited               43.44       23.02 ms    ±14.21%       23.42 ms       27.42 ms
10 added, 10 removed, 10 edited            22.85       43.76 ms     ±6.85%       43.98 ms       49.40 ms
1% added, 1% removed, 1% edited            13.62       73.45 ms     ±6.04%       74.18 ms       82.63 ms
100% modules added                          4.17      240.04 ms     ±3.68%      239.14 ms      254.60 ms
100% modules removed                        0.72     1387.87 ms     ±0.65%     1387.13 ms     1398.38 ms
33% added, 33% removed, 34% edited          0.63     1575.84 ms     ±2.95%     1566.98 ms     1643.63 ms
100% modules edited                         0.28     3632.66 ms     ±0.31%     3634.82 ms     3642.58 ms

Comparison: 
no module changes                      129032.75
1 module added                           2311.25 - 55.83x slower +0.42 ms
1 module removed                           80.47 - 1603.40x slower +12.42 ms
1 module edited                            74.77 - 1725.73x slower +13.37 ms
1 added, 1 removed, 1 edited               67.03 - 1924.98x slower +14.91 ms
3 added, 3 removed, 3 edited               43.44 - 2970.50x slower +23.01 ms
10 added, 10 removed, 10 edited            22.85 - 5646.12x slower +43.75 ms
1% added, 1% removed, 1% edited            13.62 - 9477.09x slower +73.44 ms
100% modules added                          4.17 - 30972.96x slower +240.03 ms
100% modules removed                        0.72 - 179081.09x slower +1387.87 ms
33% added, 33% removed, 34% edited          0.63 - 203334.56x slower +1575.83 ms
100% modules edited                         0.28 - 468732.60x slower +3632.66 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        1.11 M      901.73 ns    ±56.24%         750 ns     2528.14 ns
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       20.60 K       48.55 μs     ±3.77%       48.56 μs       57.03 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
2 vertices         1.60 M      626.35 ns    ±70.15%         584 ns     2492.86 ns
4 vertices         1.15 M      867.02 ns    ±40.40%         792 ns     2063.68 ns
8 vertices         1.02 M      981.95 ns    ±29.87%         958 ns     2266.12 ns
16 vertices        0.79 M     1261.71 ns    ±29.81%        1250 ns     2858.90 ns
32 vertices        0.48 M     2104.55 ns    ±85.52%        2041 ns     4288.16 ns
1 vertex        0.00005 M 20805842.02 ns     ±1.44% 20644685.40 ns 21533733.30 ns

Comparison: 
2 vertices         1.60 M
4 vertices         1.15 M - 1.38x slower +240.67 ns
8 vertices         1.02 M - 1.57x slower +355.60 ns
16 vertices        0.79 M - 2.01x slower +635.36 ns
32 vertices        0.48 M - 3.36x slower +1478.20 ns
1 vertex        0.00005 M - 33217.59x slower +20805215.67 ns
```


### ✅ compiler » create_page_entry_files_5

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/5          1.46      683.81 ms     ±0.40%      683.82 ms      689.59 ms
```


### ✅ compiler » create_runtime_entry_file_4

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/4         11.10       90.06 ms     ±2.91%       90.24 ms       96.18 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.47 K      223.68 μs     ±5.25%      221.58 μs      255.12 μs
100% modules added                        3.70 K      270.58 μs     ±7.89%      259.67 μs      364.17 μs
33% added, 33% removed, 34% edited        2.74 K      364.83 μs     ±8.52%      363.37 μs      461.17 μs
1 module added                            1.82 K      548.79 μs     ±3.62%      543.08 μs      628.12 μs
3 added, 3 removed, 3 edited              1.82 K      549.45 μs     ±3.71%      542.79 μs      621.58 μs
1% added, 1% removed, 1% edited           1.79 K      558.91 μs     ±4.50%      559.46 μs      644.04 μs
1 added, 1 removed, 1 edited              1.77 K      564.61 μs     ±2.96%      563.88 μs      623.16 μs
no module changes                         1.77 K      565.23 μs     ±2.85%      564.41 μs      623.05 μs
1 module removed                          1.77 K      566.57 μs     ±3.24%      565.13 μs      635.20 μs
1 module edited                           1.76 K      566.71 μs     ±2.94%      565.75 μs      626.86 μs
10 added, 10 removed, 10 edited           1.75 K      571.36 μs     ±5.43%      564.25 μs      657.75 μs
100% modules edited                       1.73 K      578.33 μs     ±6.18%      564.67 μs      712.67 μs

Comparison: 
100% modules removed                      4.47 K
100% modules added                        3.70 K - 1.21x slower +46.89 μs
33% added, 33% removed, 34% edited        2.74 K - 1.63x slower +141.15 μs
1 module added                            1.82 K - 2.45x slower +325.11 μs
3 added, 3 removed, 3 edited              1.82 K - 2.46x slower +325.76 μs
1% added, 1% removed, 1% edited           1.79 K - 2.50x slower +335.23 μs
1 added, 1 removed, 1 edited              1.77 K - 2.52x slower +340.93 μs
no module changes                         1.77 K - 2.53x slower +341.54 μs
1 module removed                          1.77 K - 2.53x slower +342.88 μs
1 module edited                           1.76 K - 2.53x slower +343.02 μs
10 added, 10 removed, 10 edited           1.75 K - 2.55x slower +347.68 μs
100% modules edited                       1.73 K - 2.59x slower +354.65 μs
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        7.89 K      0.00013 s    ±25.41%      0.00012 s      0.00027 s
do install     0.00010 K         9.87 s     ±0.00%         9.87 s         9.87 s

Comparison: 
no install        7.89 K
do install     0.00010 K - 77876.59x slower +9.87 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      198.07 K     0.00505 ms   ±133.47%     0.00475 ms     0.00938 ms
do load      0.0137 K       72.87 ms     ±1.62%       72.40 ms       77.47 ms

Comparison: 
no load      198.07 K
do load      0.0137 K - 14432.57x slower +72.86 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      104.51 K     0.00957 ms    ±51.28%     0.00925 ms      0.0144 ms
do load     0.00198 K      505.68 ms     ±1.23%      502.99 ms      519.03 ms

Comparison: 
no load      104.51 K
do load     0.00198 K - 52847.49x slower +505.67 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      103.18 K        9.69 μs    ±53.82%        9.38 μs       14.54 μs
do load        2.14 K      466.93 μs     ±3.27%      467.50 μs      513.04 μs

Comparison: 
no load      103.18 K
do load        2.14 K - 48.18x slower +457.23 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      124.62 K        8.02 μs    ±82.26%        7.96 μs        8.88 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache       49.54 K       20.19 μs    ±35.07%       18.54 μs       43.27 μs
no cache        30.15 K       33.17 μs    ±21.68%       31.21 μs       54.12 μs

Comparison: 
has cache       49.54 K
no cache        30.15 K - 1.64x slower +12.98 μs
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            29.81 M       33.55 ns    ±57.90%          42 ns          42 ns
is atom                12.35 M       80.95 ns  ±9719.36%          42 ns          84 ns
is Erlang module       11.27 M       88.70 ns  ±9103.90%          42 ns         167 ns
is Elixir module        9.38 M      106.62 ns  ±6272.66%          83 ns         125 ns

Comparison: 
is not atom            29.81 M
is atom                12.35 M - 2.41x slower +47.41 ns
is Erlang module       11.27 M - 2.64x slower +55.15 ns
is Elixir module        9.38 M - 3.18x slower +73.07 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           173.21 M        5.77 ns  ±4811.92%        4.20 ns        8.40 ns
is Elixir module       17.24 M       58.02 ns  ±7452.04%          42 ns          84 ns
is Erlang module       16.27 M       61.47 ns  ±7168.22%          42 ns          84 ns
is atom               0.0801 M    12476.72 ns    ±45.09%       12250 ns       17666 ns

Comparison: 
is not atom           173.21 M
is Elixir module       17.24 M - 10.05x slower +52.25 ns
is Erlang module       16.27 M - 10.65x slower +55.70 ns
is atom               0.0801 M - 2161.10x slower +12470.94 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.72 M       63.63 ns  ±9807.15%          42 ns          84 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.38 M       80.75 ns  ±5641.20%          83 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         54.62       18.31 ms     ±7.64%       18.80 ms       20.66 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         53.62       18.65 ms     ±6.78%       18.90 ms       21.13 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        255.47        3.91 ms     ±3.46%        3.89 ms        4.55 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           276.41 M        3.62 ns   ±163.15%        3.58 ns        3.75 ns
is Elixir module       22.61 M       44.22 ns  ±1792.83%          42 ns          42 ns
is Erlang module       22.46 M       44.53 ns  ±1796.78%          42 ns          42 ns
is atom               0.0789 M    12681.77 ns    ±45.69%       12459 ns       18250 ns

Comparison: 
is not atom           276.41 M
is Elixir module       22.61 M - 12.22x slower +40.60 ns
is Erlang module       22.46 M - 12.31x slower +40.91 ns
is atom               0.0789 M - 3505.40x slower +12678.15 ns
```

